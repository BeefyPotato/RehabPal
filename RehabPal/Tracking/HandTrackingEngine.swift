import ARKit
import Observation
import simd

enum TrackingProviderRole: Hashable, Sendable {
    case hand
    case world
    case plane
}

enum TrackingProviderLifecycleState: Equatable, Sendable {
    case initialized
    case running
    case paused
    case stopped
}

struct TrackingProviderStateUpdate: Equatable, Sendable {
    let roles: Set<TrackingProviderRole>
    let state: TrackingProviderLifecycleState
    let timestamp: TimeInterval
    let failureMessage: String?
}

@MainActor
@Observable
final class HandTrackingEngine: MovementObservationSource {
    private var session: ARKitSession?
    private var provider: HandTrackingProvider?
    private var worldTracking: WorldTrackingProvider?
    private var planeDetection: PlaneDetectionProvider?
    private let tableSurfaceUpdates: (@MainActor () -> AsyncStream<TableSurfaceUpdate>)?
    private let providerStateUpdates: (@MainActor () -> AsyncStream<TrackingProviderStateUpdate>)?
    private let supported: Bool
    private let runSession: @MainActor () async throws -> Void
    private let stopSession: @MainActor () -> Void
    private let usesProductionRuntime: Bool

    private var updateTask: Task<Void, Never>?
    private var planeUpdateTask: Task<Void, Never>?
    private var tableFallbackTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var eventHandler: ((LiveHandJointSessionEvent, TimeInterval) -> Void)?
    private var frames = HandJointFrameDemultiplexer()
    private var tableSelector: TableSurfaceSelector?
    private var startupGeneration = 0
    private var activeGeneration: Int?

    private(set) var latestObservation = MovementObservation.untracked(at: 0)
    private(set) var latestJointFrame: HandJointFrame?
    private(set) var tablePlacement: TablePlacement?
    private(set) var lastError: String?
    private(set) var isRunning = false
    let isFallback = false

    init() {
        session = nil
        provider = nil
        worldTracking = nil
        planeDetection = nil
        tableSurfaceUpdates = nil
        providerStateUpdates = nil
        supported = HandTrackingProvider.isSupported &&
            WorldTrackingProvider.isSupported &&
            PlaneDetectionProvider.isSupported
        usesProductionRuntime = true
        runSession = {}
        stopSession = {}
    }

    /// Injectable session boundary used to prove cancellation and generation
    /// ordering without constructing ARKit providers in unit tests.
    init(
        isSupported: Bool,
        runSession: @escaping @MainActor () async throws -> Void,
        stopSession: @escaping @MainActor () -> Void,
        tableSurfaceUpdates: (@MainActor () -> AsyncStream<TableSurfaceUpdate>)? = nil,
        providerStateUpdates: (@MainActor () -> AsyncStream<TrackingProviderStateUpdate>)? = nil
    ) {
        session = nil
        provider = nil
        worldTracking = nil
        planeDetection = nil
        supported = isSupported
        usesProductionRuntime = false
        self.runSession = runSession
        self.stopSession = stopSession
        self.tableSurfaceUpdates = tableSurfaceUpdates
        self.providerStateUpdates = providerStateUpdates
    }

    var isSupported: Bool { supported }

    var viewerPosition: SIMD3<Float>? {
        guard let worldTracking,
              let anchor = worldTracking.queryDeviceAnchor(
                  atTimestamp: ProcessInfo.processInfo.systemUptime
              ), anchor.isTracked else {
            return nil
        }
        return anchor.originFromAnchorTransform.translation
    }

    func start() async throws {
        guard isSupported else {
            let message = "Hand tracking is unavailable in this environment."
            lastError = message
            throw HandTrackingSessionError.unavailable(message)
        }

        startupGeneration += 1
        let generation = startupGeneration
        activeGeneration = nil
        isRunning = false
        cancelUpdateTasks()
        if usesProductionRuntime {
            session?.stop()
            session = nil
            provider = nil
            worldTracking = nil
            planeDetection = nil
            let freshSession = ARKitSession()
            let freshHand = HandTrackingProvider()
            let freshWorld = WorldTrackingProvider()
            let freshPlane = PlaneDetectionProvider(alignments: [.horizontal])
            session = freshSession
            provider = freshHand
            worldTracking = freshWorld
            planeDetection = freshPlane
        }
        clearPublishedFrames(at: ProcessInfo.processInfo.systemUptime)
        clearPublishedTable()

        do {
            if usesProductionRuntime,
               let session, let provider, let worldTracking, let planeDetection {
                try await session.run([provider, worldTracking, planeDetection])
            } else {
                try await runSession()
            }
        } catch {
            guard generation == startupGeneration else {
                throw CancellationError()
            }
            activeGeneration = nil
            isRunning = false
            if error is CancellationError || Task.isCancelled {
                invalidate(generation, stopUnderlyingSession: true)
                throw CancellationError()
            }
            lastError = "Hand tracking could not start: \(error.localizedDescription)"
            throw error
        }

        guard generation == startupGeneration else {
            throw CancellationError()
        }
        guard !Task.isCancelled else {
            invalidate(generation, stopUnderlyingSession: true)
            throw CancellationError()
        }

        activeGeneration = generation
        isRunning = true
        lastError = nil
        startUpdateTasks(for: generation)
    }

    func stop() {
        startupGeneration += 1
        activeGeneration = nil
        isRunning = false
        cancelUpdateTasks()
        if usesProductionRuntime {
            session?.stop()
            session = nil
            provider = nil
            worldTracking = nil
            planeDetection = nil
        } else {
            stopSession()
        }
        clearPublishedFrames(at: ProcessInfo.processInfo.systemUptime)
        clearPublishedTable()
    }

    private func cancelUpdateTasks() {
        updateTask?.cancel()
        updateTask = nil
        eventTask?.cancel()
        eventTask = nil
        planeUpdateTask?.cancel()
        planeUpdateTask = nil
        tableFallbackTask?.cancel()
        tableFallbackTask = nil
    }

    func jointFrame(for hand: AffectedHand) -> HandJointFrame? {
        frames.frame(for: hand)
    }

    func setEventHandler(
        _ handler: @escaping (LiveHandJointSessionEvent, TimeInterval) -> Void
    ) {
        eventHandler = handler
    }

    private func startUpdateTasks(for generation: Int) {
        updateTask?.cancel()
        if let provider {
            updateTask = Task { [weak self] in
                for await update in provider.anchorUpdates {
                    guard !Task.isCancelled else { return }
                    self?.consume(update, generation: generation)
                }
            }
        }

        let scanStartedAt = ProcessInfo.processInfo.systemUptime
        tableSelector = TableSurfaceSelector(scanStartedAt: scanStartedAt)
        planeUpdateTask?.cancel()
        if let planeDetection {
            planeUpdateTask = Task { [weak self] in
                for await update in planeDetection.anchorUpdates {
                    guard !Task.isCancelled else { return }
                    self?.consume(update, generation: generation)
                }
            }
        } else if let tableSurfaceUpdates {
            let updates = tableSurfaceUpdates()
            planeUpdateTask = Task { [weak self] in
                for await update in updates {
                    guard !Task.isCancelled else { return }
                    self?.consume(update, generation: generation)
                }
            }
        }

        scheduleTableFallback(for: generation, scanStartedAt: scanStartedAt)

        eventTask?.cancel()
        if let session {
            eventTask = Task { [weak self] in
                for await event in session.events {
                    guard !Task.isCancelled else { return }
                    self?.consume(event, generation: generation)
                }
            }
        } else if let providerStateUpdates {
            let updates = providerStateUpdates()
            eventTask = Task { [weak self] in
                for await update in updates {
                    guard !Task.isCancelled else { return }
                    self?.consume(update, generation: generation)
                }
            }
        }
    }

    private func scheduleTableFallback(
        for generation: Int,
        scanStartedAt: TimeInterval
    ) {
        tableFallbackTask?.cancel()
        tableFallbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            self?.publishTableFallback(
                generation: generation,
                at: scanStartedAt + 3
            )
        }
    }

    private func consume(
        _ update: AnchorUpdate<PlaneAnchor>,
        generation: Int
    ) {
        let tableUpdate: TableSurfaceUpdate
        switch update.event {
        case .added:
            tableUpdate = .added(detectedSurface(
                from: update.anchor,
                timestamp: update.timestamp
            ))
        case .updated:
            tableUpdate = .updated(detectedSurface(
                from: update.anchor,
                timestamp: update.timestamp
            ))
        case .removed:
            tableUpdate = .removed(
                id: update.anchor.id,
                timestamp: update.timestamp
            )
        @unknown default:
            tableUpdate = .removed(
                id: update.anchor.id,
                timestamp: update.timestamp
            )
        }
        consume(tableUpdate, generation: generation)
    }

    private func detectedSurface(
        from anchor: PlaneAnchor,
        timestamp: TimeInterval
    ) -> DetectedTableSurface {
        let extent = anchor.geometry.extent
        return DetectedTableSurface(
            id: anchor.id,
            timestamp: timestamp,
            transform: simd_mul(
                anchor.originFromAnchorTransform,
                extent.anchorFromExtentTransform
            ),
            extent: [extent.width, extent.height],
            isTracked: true
        )
    }

    private func consume(
        _ update: TableSurfaceUpdate,
        generation: Int
    ) {
        guard activeGeneration == generation else { return }
        let timestamp: TimeInterval
        switch update {
        case let .added(surface), let .updated(surface):
            timestamp = surface.timestamp
        case let .removed(_, removedAt):
            timestamp = removedAt
        }
        tablePlacement = tableSelector?.receive(update, at: timestamp)
    }

    private func publishTableFallback(
        generation: Int,
        at timestamp: TimeInterval
    ) {
        guard activeGeneration == generation else { return }
        tablePlacement = tableSelector?.placement(at: timestamp)
    }

    private func consume(
        _ update: AnchorUpdate<HandAnchor>,
        generation: Int
    ) {
        guard activeGeneration == generation else { return }
        guard let hand = affectedHand(for: update.anchor.chirality) else { return }

        switch update.event {
        case .added:
            applyTrackedUpdate(
                .added,
                anchor: update.anchor,
                hand: hand,
                timestamp: update.timestamp
            )
        case .updated:
            applyTrackedUpdate(
                .updated,
                anchor: update.anchor,
                hand: hand,
                timestamp: update.timestamp
            )
        case .removed:
            frames.apply(.removed(hand: hand, timestamp: update.timestamp))
            publishMostRecentFrame(removing: hand, at: update.timestamp)
        @unknown default:
            frames.apply(.removed(hand: hand, timestamp: update.timestamp))
            publishMostRecentFrame(removing: hand, at: update.timestamp)
        }
    }

    private enum TrackedUpdateKind {
        case added
        case updated
    }

    private func applyTrackedUpdate(
        _ kind: TrackedUpdateKind,
        anchor: HandAnchor,
        hand: AffectedHand,
        timestamp: TimeInterval
    ) {
        guard let frame = HandJointFrame(anchor: anchor, timestamp: timestamp) else {
            frames.apply(.removed(hand: hand, timestamp: timestamp))
            publishMostRecentFrame(removing: hand, at: timestamp)
            return
        }
        switch kind {
        case .added:
            frames.apply(.added(frame))
        case .updated:
            frames.apply(.updated(frame))
        }
        latestJointFrame = frame
        latestObservation = MovementObservation(acceptedJointFrame: frame)
    }

    private func publishMostRecentFrame(
        removing hand: AffectedHand,
        at timestamp: TimeInterval
    ) {
        let unaffected: AffectedHand = hand == .left ? .right : .left
        latestJointFrame = frames.frame(for: unaffected)
        latestObservation = latestJointFrame.map(MovementObservation.init(acceptedJointFrame:))
            ?? .untracked(at: timestamp)
    }

    private func consume(_ event: ARKitSession.Event, generation: Int) {
        guard activeGeneration == generation else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        switch event {
        case let .authorizationChanged(_, status):
            if status == .denied {
                eventHandler?(.authorizationDenied, timestamp)
            }
        case let .dataProviderStateChanged(dataProviders, newState, error):
            let roles = Set(dataProviders.compactMap { provider in
                if provider is HandTrackingProvider { return TrackingProviderRole.hand }
                if provider is WorldTrackingProvider { return TrackingProviderRole.world }
                if provider is PlaneDetectionProvider { return TrackingProviderRole.plane }
                return nil
            })
            let state: TrackingProviderLifecycleState
            switch newState {
            case .initialized:
                state = .initialized
            case .running:
                state = .running
            case .paused:
                state = .paused
            case .stopped:
                state = .stopped
            @unknown default:
                state = .paused
            }
            consume(TrackingProviderStateUpdate(
                roles: roles,
                state: state,
                timestamp: timestamp,
                failureMessage: error?.localizedDescription
            ), generation: generation)
        @unknown default:
            break
        }
    }

    private func consume(
        _ update: TrackingProviderStateUpdate,
        generation: Int
    ) {
        guard activeGeneration == generation else { return }
        guard update.timestamp.isFinite else { return }

        if update.roles.contains(.plane),
           update.state == .paused || update.state == .stopped {
            tableSelector = TableSurfaceSelector(scanStartedAt: update.timestamp)
            tablePlacement = nil
            scheduleTableFallback(
                for: generation,
                scanStartedAt: update.timestamp
            )
        }

        guard !update.roles.isDisjoint(with: [.hand, .world]) else { return }
        switch update.state {
        case .paused:
            eventHandler?(.interrupted, update.timestamp)
        case .stopped:
            eventHandler?(
                .providerFailed(
                    update.failureMessage ?? "ARKit data provider stopped"
                ),
                update.timestamp
            )
        case .initialized, .running:
            break
        }
    }

    private func invalidate(
        _ generation: Int,
        stopUnderlyingSession: Bool
    ) {
        guard generation == startupGeneration else { return }
        startupGeneration += 1
        activeGeneration = nil
        isRunning = false
        cancelUpdateTasks()
        if stopUnderlyingSession {
            if usesProductionRuntime {
                session?.stop()
                session = nil
                provider = nil
                worldTracking = nil
                planeDetection = nil
            } else {
                stopSession()
            }
        }
        clearPublishedFrames(at: ProcessInfo.processInfo.systemUptime)
        clearPublishedTable()
    }

    private func clearPublishedFrames(at timestamp: TimeInterval) {
        frames.removeAll()
        latestJointFrame = nil
        latestObservation = .untracked(at: timestamp)
    }

    private func clearPublishedTable() {
        tableSelector = nil
        tablePlacement = nil
    }

    private func affectedHand(
        for chirality: HandAnchor.Chirality
    ) -> AffectedHand? {
        switch chirality {
        case .left:
            .left
        case .right:
            .right
        @unknown default:
            nil
        }
    }
}

extension HandTrackingEngine: LiveHandJointSession {}

private enum HandTrackingSessionError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        guard case let .unavailable(message) = self else { return nil }
        return message
    }
}
