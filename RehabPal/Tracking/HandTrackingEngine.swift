import ARKit
import Observation
import simd

@MainActor
@Observable
final class HandTrackingEngine: MovementObservationSource {
    private let session: ARKitSession?
    private let provider: HandTrackingProvider?
    private let worldTracking: WorldTrackingProvider?
    private let supported: Bool
    private let runSession: @MainActor () async throws -> Void
    private let stopSession: @MainActor () -> Void

    private var updateTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var eventHandler: ((LiveHandJointSessionEvent, TimeInterval) -> Void)?
    private var frames = HandJointFrameDemultiplexer()
    private var startupGeneration = 0
    private var activeGeneration: Int?

    private(set) var latestObservation = MovementObservation.untracked(at: 0)
    private(set) var latestJointFrame: HandJointFrame?
    private(set) var lastError: String?
    private(set) var isRunning = false
    let isFallback = false

    init() {
        let session = ARKitSession()
        let provider = HandTrackingProvider()
        let worldTracking = WorldTrackingProvider()
        self.session = session
        self.provider = provider
        self.worldTracking = worldTracking
        supported = HandTrackingProvider.isSupported && WorldTrackingProvider.isSupported
        runSession = {
            try await session.run([provider, worldTracking])
        }
        stopSession = {
            session.stop()
        }
    }

    /// Injectable session boundary used to prove cancellation and generation
    /// ordering without constructing ARKit providers in unit tests.
    init(
        isSupported: Bool,
        runSession: @escaping @MainActor () async throws -> Void,
        stopSession: @escaping @MainActor () -> Void
    ) {
        session = nil
        provider = nil
        worldTracking = nil
        supported = isSupported
        self.runSession = runSession
        self.stopSession = stopSession
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

        do {
            try await runSession()
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
        updateTask?.cancel()
        updateTask = nil
        eventTask?.cancel()
        eventTask = nil
        stopSession()
        clearPublishedFrames(at: ProcessInfo.processInfo.systemUptime)
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

        eventTask?.cancel()
        if let session {
            eventTask = Task { [weak self] in
                for await event in session.events {
                    guard !Task.isCancelled else { return }
                    self?.consume(event, generation: generation)
                }
            }
        }
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
        case let .dataProviderStateChanged(_, newState, error):
            switch newState {
            case .paused:
                eventHandler?(.interrupted, timestamp)
            case .stopped:
                eventHandler?(
                    .providerFailed(error?.localizedDescription ?? "ARKit data provider stopped"),
                    timestamp
                )
            case .initialized, .running:
                break
            @unknown default:
                eventHandler?(.interrupted, timestamp)
            }
        @unknown default:
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
        updateTask?.cancel()
        updateTask = nil
        eventTask?.cancel()
        eventTask = nil
        if stopUnderlyingSession {
            stopSession()
        }
        clearPublishedFrames(at: ProcessInfo.processInfo.systemUptime)
    }

    private func clearPublishedFrames(at timestamp: TimeInterval) {
        frames.removeAll()
        latestJointFrame = nil
        latestObservation = .untracked(at: timestamp)
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
