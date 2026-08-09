import Foundation
import Observation

struct RehabLiveStartToken: Equatable, Sendable {
    fileprivate let generation: Int
    let request: RehabSessionRequest
}

struct RehabDemoStartToken: Equatable, Sendable {
    fileprivate let generation: Int
    fileprivate let request: RehabSessionRequest
}

@MainActor
@Observable
final class RehabSessionCoordinator {
    nonisolated static let immersiveSpaceID = "rehab-session"
    nonisolated static let recalibrationDelay: TimeInterval = 2
    nonisolated static let maximumPendingDiagnosticObservations = 256
    nonisolated static let defaultMaximumFrameAge: TimeInterval = 0.2

    private let prescription: Prescription
    private let liveTracking: any LiveHandJointSession
    private let maximumFrameAge: TimeInterval
    private var demoTracking: SyntheticMovementSource?
    private var trackingLossBeganAt: TimeInterval?
    private var jointFrameObservationSequence = 0
    private var pendingDiagnosticObservations: [HandJointFrameObservation] = []
    private var requiredJoints: Set<HandJoint> = []
    private var latestFrameReceivedAt: TimeInterval?
    private var providerInterruptionAt: TimeInterval?

    private var startupGeneration = 0
    private var preparedLiveStart: RehabLiveStartToken?
    private var resetGeneration = 0
    private var requiredCalibrationGeneration: Int?
    private var calibratedProcessorGeneration: Int?

    private(set) var phase: RehabSessionPhase = .idle
    private(set) var latestAcceptedJointFrame: HandJointFrame?
    private(set) var monitoringGeneration = 0
    private(set) var phaseRevision = 0
    private(set) var pendingProcessorResetGeneration: Int?

    init(
        prescription: Prescription,
        liveTracking: any LiveHandJointSession,
        maximumFrameAge: TimeInterval = RehabSessionCoordinator.defaultMaximumFrameAge
    ) {
        self.prescription = prescription
        self.liveTracking = liveTracking
        self.maximumFrameAge = max(0, maximumFrameAge)
        liveTracking.setEventHandler { [weak self] event, timestamp in
            self?.receiveLiveTrackingEvent(event, at: timestamp)
        }
    }

    convenience init(prescription: Prescription) {
        self.init(prescription: prescription, liveTracking: HandTrackingEngine())
    }

    var activeRequest: RehabSessionRequest? {
        switch phase {
        case let .starting(request),
             let .active(request, _, _),
             let .paused(request, _, _):
            request
        case let .failed(failure):
            failure.request
        case let .completed(outcome):
            outcome.request
        case .idle:
            nil
        }
    }

    var progress: SessionProgress? {
        switch phase {
        case let .active(_, progress, _), let .paused(_, progress, _):
            progress
        case let .completed(outcome):
            outcome.progress
        case .idle, .starting, .failed:
            nil
        }
    }

    var provenance: SessionProvenance? {
        switch phase {
        case let .active(_, _, provenance):
            provenance
        case .paused:
            .live
        case let .completed(outcome):
            outcome.provenance
        case .idle, .starting, .failed:
            nil
        }
    }

    var authorization: ActiveRehabSession? {
        guard let request = activeRequest, let provenance else { return nil }
        return ActiveRehabSession(request: request, provenance: provenance)
    }

    var pauseReason: SessionPauseReason? {
        guard case let .paused(_, _, reason) = phase else { return nil }
        return reason
    }

    var canConfirmRecalibration: Bool {
        guard case let .paused(request, _, reason) = phase,
              case .trackingLost(requiresRecalibration: true) = reason,
              let generation = requiredCalibrationGeneration,
              pendingProcessorResetGeneration == nil,
              calibratedProcessorGeneration == generation,
              let frame = latestAcceptedJointFrame,
              let receivedAt = latestFrameReceivedAt else {
            return false
        }
        return isUsable(frame, for: request, receivedAt: receivedAt)
    }

    var isUsingDemoMode: Bool { provenance == .demo }
    var squeezeCloseThreshold: Float { prescription.squeezeCloseThreshold }
    var squeezeReopenThreshold: Float { prescription.squeezeReopenThreshold }
    var squeezeHoldSeconds: TimeInterval { prescription.squeezeHoldSeconds }
    var wristDiagnosticPrescription: WristDiagnosticPrescription { prescription.wristDiagnostic }
    var fingerDiagnosticPrescription: FingerDiagnosticPrescription { prescription.fingerDiagnostic }

    var currentFrame: HandJointFrame? {
        latestAcceptedJointFrame
    }

    var currentViewerPosition: SIMD3<Float>? {
        guard provenance != .demo else { return nil }
        return liveTracking.viewerPosition
    }

    var currentTablePlacement: TablePlacement? {
        guard case .exercise(.sheepDrop) = activeRequest?.experience else {
            return nil
        }
        switch phase {
        case .active(_, _, .live), .paused:
            return liveTracking.tablePlacement
        case .active(_, _, .demo):
            return .estimatedReference
        case .idle, .starting, .failed, .completed:
            return nil
        }
    }

    var compatibilityObservation: MovementObservation {
        guard let currentFrame else {
            return .untracked(at: ProcessInfo.processInfo.systemUptime)
        }
        return MovementObservation(acceptedJointFrame: currentFrame)
    }

    var shouldMonitorFrames: Bool {
        switch phase {
        case .active(_, _, .live), .paused:
            true
        case .idle, .starting, .active(_, _, .demo), .failed, .completed:
            false
        }
    }

    /// Validates and reserves a generation without touching ARKit. The caller
    /// opens the mixed immersive space, then supplies this token to
    /// `startPreparedLive`, which is the only operation that invokes start().
    func prepareLiveStart(_ request: RehabSessionRequest) -> RehabLiveStartToken? {
        invalidateStartup()
        cleanUpTracking()
        resetPublishedTrackingState()
        monitoringGeneration += 1

        guard request.affectedHand == prescription.affectedHand else {
            setPhase(.failed(SessionFailure(
                request: request,
                reason: .affectedHandMismatch(
                    expected: prescription.affectedHand,
                    received: request.affectedHand
                ),
                recoveryActions: [.cancel]
            )))
            return nil
        }
        guard request == prescription.sessionRequest(for: request.experience),
              request.hasValidGoal else {
            setPhase(.failed(SessionFailure(
                request: request,
                reason: .invalidGoal,
                recoveryActions: [.cancel]
            )))
            return nil
        }
        guard liveTracking.isSupported else {
            setPhase(recoverableFailure(
                request: request,
                reason: .liveTrackingUnavailable
            ))
            return nil
        }

        startupGeneration += 1
        let token = RehabLiveStartToken(
            generation: startupGeneration,
            request: request
        )
        preparedLiveStart = token
        requiredJoints = defaultRequiredJoints(for: request.experience)
        setPhase(.starting(request))
        return token
    }

    @discardableResult
    func startPreparedLive(_ token: RehabLiveStartToken) async -> Bool {
        guard isCurrent(token) else { return false }

        do {
            try await liveTracking.start()
        } catch is CancellationError {
            guard isCurrent(token) else { return false }
            if Task.isCancelled {
                cancelPreparedLive(token)
            } else {
                liveTracking.stop()
                preparedLiveStart = nil
                setPhase(recoverableFailure(
                    request: token.request,
                    reason: .liveStartupFailed("Live tracking startup was cancelled")
                ))
            }
            return false
        } catch {
            guard isCurrent(token) else { return false }
            liveTracking.stop()
            preparedLiveStart = nil
            setPhase(recoverableFailure(
                request: token.request,
                reason: .liveStartupFailed(error.localizedDescription)
            ))
            return false
        }

        guard isCurrent(token) else { return false }
        guard !Task.isCancelled else {
            cancelPreparedLive(token)
            return false
        }

        preparedLiveStart = nil
        setPhase(.active(
            request: token.request,
            progress: SessionProgress(
                completed: 0,
                goal: token.request.goal,
                partial: 0
            ),
            provenance: .live
        ))
        // The monitor task launched for `.starting` has already exited because
        // frames are only polled for an active live session. Give SwiftUI a new
        // task identity now that polling is authorized.
        monitoringGeneration += 1
        return true
    }

    func cancelPreparedLive(_ token: RehabLiveStartToken) {
        guard isCurrent(token) else { return }
        cancel()
    }

    @discardableResult
    func startDemoMode() -> Bool {
        prepareDemoStart() != nil
    }

    /// Activates the simulated source before the immersive open boundary so
    /// feature processors are constructed with explicit demo provenance.
    func prepareDemoStart() -> RehabDemoStartToken? {
        guard case let .failed(failure) = phase,
              failure.recoveryActions.contains(.enterDemoMode),
              failure.request.affectedHand == prescription.affectedHand else {
            return nil
        }
        invalidateStartup()
        cleanUpTracking()
        resetPublishedTrackingState()
        monitoringGeneration += 1
        startupGeneration += 1
        let token = RehabDemoStartToken(
            generation: startupGeneration,
            request: failure.request
        )
        let source = SyntheticMovementSource(hand: prescription.affectedHand)
        demoTracking = source
        latestAcceptedJointFrame = source.latestJointFrame
        latestFrameReceivedAt = source.latestJointFrame?.timestamp
        trackingLossBeganAt = nil
        requiredJoints = defaultRequiredJoints(for: failure.request.experience)
        setPhase(.active(
            request: failure.request,
            progress: SessionProgress(
                completed: 0,
                goal: failure.request.goal,
                partial: 0
            ),
            provenance: .demo
        ))
        return token
    }

    func completePreparedDemo(_ token: RehabDemoStartToken) -> Bool {
        isCurrent(token)
    }

    func cancelPreparedDemo(_ token: RehabDemoStartToken) {
        guard isCurrent(token) else { return }
        cancel()
    }

    func failPreparedDemoOpen(
        _ token: RehabDemoStartToken,
        message: String
    ) {
        guard isCurrent(token) else { return }
        failImmersiveSpace(message)
    }

    func accept(_ newProgress: SessionProgress) {
        guard case let .active(request, currentProgress, provenance) = phase,
              newProgress.goal == request.goal,
              newProgress.completed >= currentProgress.completed,
              newProgress.completed <= request.goal,
              newProgress.partial.isFinite,
              (0...1).contains(newProgress.partial),
              newProgress != currentProgress else {
            return
        }
        setPhase(.active(
            request: request,
            progress: newProgress,
            provenance: provenance
        ))
    }

    func updateRequiredJoints(_ joints: Set<HandJoint>) {
        guard !joints.isEmpty else { return }
        requiredJoints = joints
    }

    func pollLiveTracking(at timestamp: TimeInterval) {
        guard let request = activeRequest else { return }
        receiveJointFrame(
            liveTracking.jointFrame(for: request.affectedHand),
            at: timestamp
        )
    }

    func receiveJointFrame(_ frame: HandJointFrame?, at timestamp: TimeInterval) {
        guard let request = activeRequest,
              var currentProgress = progress,
              provenance == .live || pauseReason != nil else {
            return
        }

        let usableFrame = frame.flatMap {
            isUsable($0, for: request, receivedAt: timestamp) ? $0 : nil
        }
        if usableFrame != nil {
            providerInterruptionAt = nil
        }
        publishDiagnosticObservation(
            frame: usableFrame,
            request: request,
            timestamp: timestamp
        )

        guard let usableFrame else {
            registerTrackingLoss(
                request: request,
                progress: &currentProgress,
                at: timestamp
            )
            return
        }

        latestAcceptedJointFrame = usableFrame
        latestFrameReceivedAt = timestamp
        guard case let .paused(_, pausedProgress, reason) = phase else { return }

        if case .trackingLost(requiresRecalibration: true) = reason {
            return
        }
        if let trackingLossBeganAt,
           timestamp - trackingLossBeganAt >= Self.recalibrationDelay {
            requireProcessorRecalibration()
            setPhase(.paused(
                request: request,
                progress: pausedProgress,
                reason: .trackingLost(requiresRecalibration: true)
            ))
            return
        }
        trackingLossBeganAt = nil
        setPhase(.active(
            request: request,
            progress: pausedProgress,
            provenance: .live
        ))
    }

    /// Returns every retained diagnostic poll in publication order, then
    /// clears the bounded buffer so a render pass cannot consume one twice.
    func consumeDiagnosticObservations() -> [HandJointFrameObservation] {
        let observations = pendingDiagnosticObservations
        pendingDiagnosticObservations.removeAll(keepingCapacity: true)
        return observations
    }

    @discardableResult
    func acknowledgeProcessorReset(_ generation: Int) -> Bool {
        guard case let .paused(_, _, reason) = phase,
              case .trackingLost(requiresRecalibration: true) = reason,
              requiredCalibrationGeneration == generation,
              pendingProcessorResetGeneration == generation else {
            return false
        }
        pendingProcessorResetGeneration = nil
        return true
    }

    @discardableResult
    func acknowledgeProcessorCalibration(
        generation: Int,
        frameTimestamp: TimeInterval
    ) -> Bool {
        guard case let .paused(request, _, reason) = phase,
              case .trackingLost(requiresRecalibration: true) = reason,
              requiredCalibrationGeneration == generation,
              pendingProcessorResetGeneration == nil,
              let frame = latestAcceptedJointFrame,
              frame.timestamp == frameTimestamp,
              let receivedAt = latestFrameReceivedAt,
              isUsable(frame, for: request, receivedAt: receivedAt) else {
            return false
        }
        calibratedProcessorGeneration = generation
        return true
    }

    @discardableResult
    func confirmRecalibration() -> Bool {
        guard case let .paused(request, progress, reason) = phase,
              case .trackingLost(requiresRecalibration: true) = reason,
              let generation = requiredCalibrationGeneration,
              calibratedProcessorGeneration == generation,
              canConfirmRecalibration else {
            return false
        }
        trackingLossBeganAt = nil
        requiredCalibrationGeneration = nil
        calibratedProcessorGeneration = nil
        setPhase(.active(
            request: request,
            progress: progress,
            provenance: .live
        ))
        return true
    }

    @discardableResult
    func finish(with payload: SessionOutcomePayload) -> RehabSessionOutcome? {
        guard case let .active(request, progress, provenance) = phase,
              progress.completed == progress.goal,
              payload.matches(request) else {
            return nil
        }
        let outcome = RehabSessionOutcome(
            request: request,
            progress: progress,
            provenance: provenance,
            payload: payload
        )
        invalidateStartup()
        cleanUpTracking()
        resetPublishedTrackingState()
        setPhase(.completed(outcome))
        return outcome
    }

    func failImmersiveSpace(_ message: String) {
        guard let request = activeRequest else { return }
        invalidateStartup()
        cleanUpTracking()
        resetPublishedTrackingState()
        setPhase(recoverableFailure(
            request: request,
            reason: .immersiveSpaceFailed(message)
        ))
    }

    func cancel() {
        invalidateStartup()
        cleanUpTracking()
        resetPublishedTrackingState()
        monitoringGeneration += 1
        setPhase(.idle)
    }

    private func receiveLiveTrackingEvent(
        _ event: LiveHandJointSessionEvent,
        at timestamp: TimeInterval
    ) {
        switch event {
        case .interrupted:
            if timestamp.isFinite {
                providerInterruptionAt = max(
                    providerInterruptionAt ?? timestamp,
                    timestamp
                )
            }
            receiveJointFrame(nil, at: timestamp)
        case .authorizationDenied:
            failLiveSession(reason: .liveAuthorizationDenied)
        case let .providerFailed(message):
            failLiveSession(reason: .liveProviderFailed(message))
        }
    }

    private func failLiveSession(reason: SessionFailure.Reason) {
        guard let request = activeRequest else { return }
        switch phase {
        case .starting, .active(_, _, .live), .paused:
            break
        case .idle, .active(_, _, .demo), .failed, .completed:
            return
        }
        invalidateStartup()
        cleanUpTracking()
        resetPublishedTrackingState()
        setPhase(recoverableFailure(request: request, reason: reason))
    }

    private func registerTrackingLoss(
        request: RehabSessionRequest,
        progress: inout SessionProgress,
        at timestamp: TimeInterval
    ) {
        if trackingLossBeganAt == nil {
            trackingLossBeganAt = timestamp
        }
        progress = progress.discardingPartialMotion()
        let elapsed = timestamp - (trackingLossBeganAt ?? timestamp)
        let requiresRecalibration = elapsed >= Self.recalibrationDelay
        if requiresRecalibration {
            requireProcessorRecalibration()
        }
        latestAcceptedJointFrame = nil
        latestFrameReceivedAt = nil
        setPhase(.paused(
            request: request,
            progress: progress,
            reason: .trackingLost(
                requiresRecalibration: requiresRecalibration
            )
        ))
    }

    private func requireProcessorRecalibration() {
        guard requiredCalibrationGeneration == nil else { return }
        resetGeneration += 1
        requiredCalibrationGeneration = resetGeneration
        pendingProcessorResetGeneration = resetGeneration
        calibratedProcessorGeneration = nil
    }

    private func publishDiagnosticObservation(
        frame: HandJointFrame?,
        request: RehabSessionRequest,
        timestamp: TimeInterval
    ) {
        switch request.experience {
        case .wristAssessment, .handAssessment:
            jointFrameObservationSequence += 1
            pendingDiagnosticObservations.append(HandJointFrameObservation(
                sequence: jointFrameObservationSequence,
                timestamp: timestamp,
                frame: frame
            ))
            let overflow = pendingDiagnosticObservations.count -
                Self.maximumPendingDiagnosticObservations
            if overflow > 0 {
                pendingDiagnosticObservations.removeFirst(overflow)
            }
        case .exercise:
            break
        }
    }

    private func isUsable(
        _ frame: HandJointFrame,
        for request: RehabSessionRequest,
        receivedAt timestamp: TimeInterval
    ) -> Bool {
        guard timestamp.isFinite,
              frame.timestamp.isFinite,
              frame.isForAffectedHand(request.affectedHand),
              timestamp - frame.timestamp <= maximumFrameAge,
              providerInterruptionAt.map({ frame.timestamp > $0 }) ?? true,
              frame.confidence(requiring: requiredJoints) == .good else {
            return false
        }
        return true
    }

    private func defaultRequiredJoints(
        for experience: RehabExperience
    ) -> Set<HandJoint> {
        switch experience {
        case .exercise(.balance), .wristAssessment:
            WristNeutralCalibration.requiredJoints
        case .exercise(.squeeze), .exercise(.sheepDrop):
            SqueezeHandMetrics.requiredJoints
        case .handAssessment:
            Set(FingerROMMetrics.requiredJoints(for: .thumb))
        }
    }

    private func isCurrent(_ token: RehabLiveStartToken) -> Bool {
        preparedLiveStart == token &&
        startupGeneration == token.generation &&
        phase == .starting(token.request)
    }

    private func isCurrent(_ token: RehabDemoStartToken) -> Bool {
        guard startupGeneration == token.generation,
              case let .active(request, _, .demo) = phase else {
            return false
        }
        return request == token.request
    }

    private func invalidateStartup() {
        startupGeneration += 1
        preparedLiveStart = nil
    }

    private func resetPublishedTrackingState() {
        latestAcceptedJointFrame = nil
        latestFrameReceivedAt = nil
        pendingDiagnosticObservations.removeAll(keepingCapacity: true)
        trackingLossBeganAt = nil
        providerInterruptionAt = nil
        pendingProcessorResetGeneration = nil
        requiredCalibrationGeneration = nil
        calibratedProcessorGeneration = nil
        requiredJoints.removeAll(keepingCapacity: true)
        demoTracking = nil
    }

    private func cleanUpTracking() {
        switch phase {
        case .starting, .active(_, _, .live), .paused:
            liveTracking.stop()
        case .idle, .active(_, _, .demo), .failed, .completed:
            break
        }
        demoTracking = nil
    }

    private func setPhase(_ newPhase: RehabSessionPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
        phaseRevision += 1
    }

    private func recoverableFailure(
        request: RehabSessionRequest,
        reason: SessionFailure.Reason
    ) -> RehabSessionPhase {
        .failed(SessionFailure(
            request: request,
            reason: reason,
            recoveryActions: [.retryLive, .enterDemoMode, .cancel]
        ))
    }
}
