import Foundation
import Observation

@MainActor
protocol LiveHandJointSession: AnyObject {
    var isSupported: Bool { get }
    var latestJointFrame: HandJointFrame? { get }
    func start() async throws
    func stop()
}

@MainActor
@Observable
final class RehabSessionCoordinator {
    static let immersiveSpaceID = "rehab-session"
    static let recalibrationDelay: TimeInterval = 2

    private let prescribedHand: AffectedHand
    private let liveTracking: any LiveHandJointSession
    private var demoTracking: SyntheticMovementSource?
    private var trackingLossBeganAt: TimeInterval?

    private(set) var phase: RehabSessionPhase = .idle
    private(set) var latestAcceptedJointFrame: HandJointFrame?

    init(prescription: Prescription, liveTracking: any LiveHandJointSession) {
        prescribedHand = prescription.affectedHand
        self.liveTracking = liveTracking
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
        case let .completed(outcome):
            outcome.provenance
        case .idle, .starting, .paused, .failed:
            nil
        }
    }

    var pauseReason: SessionPauseReason? {
        guard case let .paused(_, _, reason) = phase else { return nil }
        return reason
    }

    var isUsingDemoMode: Bool { provenance == .demo }

    var latestJointFrame: HandJointFrame? {
        if isUsingDemoMode {
            return demoTracking?.latestJointFrame
        }
        return liveTracking.latestJointFrame
    }

    func startLive(_ request: RehabSessionRequest) async {
        cleanUpTracking()
        latestAcceptedJointFrame = nil
        trackingLossBeganAt = nil

        guard request.affectedHand == prescribedHand else {
            phase = .failed(SessionFailure(
                request: request,
                reason: .affectedHandMismatch(
                    expected: prescribedHand,
                    received: request.affectedHand
                ),
                recoveryActions: [.cancel]
            ))
            return
        }
        guard request.goal > 0 else {
            phase = .failed(SessionFailure(
                request: request,
                reason: .invalidGoal,
                recoveryActions: [.cancel]
            ))
            return
        }
        guard liveTracking.isSupported else {
            phase = recoverableFailure(request: request, reason: .liveTrackingUnavailable)
            return
        }

        phase = .starting(request)
        do {
            try await liveTracking.start()
            guard !Task.isCancelled else {
                cancel()
                return
            }
            phase = .active(
                request: request,
                progress: SessionProgress(completed: 0, goal: request.goal, partial: 0),
                provenance: .live
            )
        } catch is CancellationError {
            cancel()
        } catch {
            liveTracking.stop()
            phase = recoverableFailure(
                request: request,
                reason: .liveStartupFailed(error.localizedDescription)
            )
        }
    }

    func retryLive() async {
        guard case let .failed(failure) = phase,
              failure.recoveryActions.contains(.retryLive) else {
            return
        }
        await startLive(failure.request)
    }

    @discardableResult
    func startDemoMode() -> Bool {
        guard case let .failed(failure) = phase,
              failure.recoveryActions.contains(.enterDemoMode),
              failure.request.affectedHand == prescribedHand else {
            return false
        }
        cleanUpTracking()
        let source = SyntheticMovementSource(hand: prescribedHand)
        demoTracking = source
        latestAcceptedJointFrame = source.latestJointFrame
        trackingLossBeganAt = nil
        phase = .active(
            request: failure.request,
            progress: SessionProgress(completed: 0, goal: failure.request.goal, partial: 0),
            provenance: .demo
        )
        return true
    }

    func accept(_ newProgress: SessionProgress) {
        guard case let .active(request, currentProgress, provenance) = phase,
              newProgress.goal == request.goal,
              newProgress.completed >= currentProgress.completed,
              newProgress.completed <= request.goal,
              newProgress.partial.isFinite,
              (0...1).contains(newProgress.partial) else {
            return
        }
        phase = .active(request: request, progress: newProgress, provenance: provenance)
    }

    func receiveJointFrame(_ frame: HandJointFrame?, at timestamp: TimeInterval) {
        guard let request = activeRequest,
              var currentProgress = progress,
              provenance == .live || pauseReason != nil else {
            return
        }

        guard let frame, frame.isForAffectedHand(request.affectedHand) else {
            if trackingLossBeganAt == nil {
                trackingLossBeganAt = timestamp
            }
            currentProgress = currentProgress.discardingPartialMotion()
            let elapsed = timestamp - (trackingLossBeganAt ?? timestamp)
            phase = .paused(
                request: request,
                progress: currentProgress,
                reason: .trackingLost(
                    requiresRecalibration: elapsed >= Self.recalibrationDelay
                )
            )
            latestAcceptedJointFrame = nil
            return
        }

        latestAcceptedJointFrame = frame
        guard case let .paused(_, pausedProgress, reason) = phase else { return }
        if case .trackingLost(requiresRecalibration: true) = reason {
            return
        }
        if let trackingLossBeganAt,
           timestamp - trackingLossBeganAt >= Self.recalibrationDelay {
            phase = .paused(
                request: request,
                progress: pausedProgress,
                reason: .trackingLost(requiresRecalibration: true)
            )
            return
        }
        trackingLossBeganAt = nil
        phase = .active(request: request, progress: pausedProgress, provenance: .live)
    }

    @discardableResult
    func confirmRecalibration() -> Bool {
        guard case let .paused(request, progress, reason) = phase,
              case .trackingLost(requiresRecalibration: true) = reason,
              latestAcceptedJointFrame?.isForAffectedHand(request.affectedHand) == true else {
            return false
        }
        trackingLossBeganAt = nil
        phase = .active(request: request, progress: progress, provenance: .live)
        return true
    }

    @discardableResult
    func finish(with payload: SessionOutcomePayload) -> RehabSessionOutcome? {
        guard case let .active(request, progress, provenance) = phase,
              progress.completed == progress.goal,
              payload.matches(request.experience) else {
            return nil
        }
        let outcome = RehabSessionOutcome(
            request: request,
            progress: progress,
            provenance: provenance,
            payload: payload
        )
        cleanUpTracking()
        phase = .completed(outcome)
        return outcome
    }

    func failImmersiveSpace(_ message: String) {
        guard let request = activeRequest else { return }
        cleanUpTracking()
        phase = recoverableFailure(
            request: request,
            reason: .immersiveSpaceFailed(message)
        )
    }

    func cancel() {
        cleanUpTracking()
        latestAcceptedJointFrame = nil
        trackingLossBeganAt = nil
        phase = .idle
    }

    private func cleanUpTracking() {
        if case .active(_, _, .live) = phase {
            liveTracking.stop()
        } else if case .starting = phase {
            liveTracking.stop()
        } else if case .paused = phase {
            liveTracking.stop()
        }
        demoTracking = nil
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

private extension SessionOutcomePayload {
    func matches(_ experience: RehabExperience) -> Bool {
        switch (experience, self) {
        case let (.exercise(exercise), .gameplay(result)):
            result.exercise == exercise
        case (.wristAssessment, .wristAssessment):
            true
        case (.handAssessment, .handAssessment):
            true
        default:
            false
        }
    }
}
