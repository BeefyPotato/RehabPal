import Foundation

enum RehabExperience: Equatable, Hashable, Sendable {
    case exercise(ExerciseKind)
    case wristAssessment
    case handAssessment
}

struct RehabSessionRequest: Equatable, Hashable, Sendable {
    let experience: RehabExperience
    let affectedHand: AffectedHand
    let goal: Int

    init(experience: RehabExperience, prescription: Prescription, goal: Int) {
        self.init(
            experience: experience,
            affectedHand: prescription.affectedHand,
            goal: goal
        )
    }

    init(experience: RehabExperience, affectedHand: AffectedHand, goal: Int) {
        self.experience = experience
        self.affectedHand = affectedHand
        self.goal = goal
    }
}

struct SessionProgress: Equatable, Sendable {
    let completed: Int
    let goal: Int
    let partial: Double

    init(completed: Int, goal: Int, partial: Double) {
        self.completed = completed
        self.goal = goal
        self.partial = partial
    }

    func discardingPartialMotion() -> SessionProgress {
        SessionProgress(completed: completed, goal: goal, partial: 0)
    }
}

enum SessionProvenance: Equatable, Sendable {
    case live
    case demo

    var isSimulated: Bool { self == .demo }
}

enum SessionOutcomePayload: Equatable, Sendable {
    case gameplay(GameplayResult)
    case wristAssessment(AssessmentResult.WristResult)
    case handAssessment([HandDigit: DigitROMSummary])
}

struct RehabSessionOutcome: Equatable, Sendable {
    let request: RehabSessionRequest
    let progress: SessionProgress
    let provenance: SessionProvenance
    let payload: SessionOutcomePayload
}

enum SessionRecoveryAction: Equatable, Sendable {
    case retryLive
    case enterDemoMode
    case cancel
}

struct SessionFailure: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case affectedHandMismatch(expected: AffectedHand, received: AffectedHand)
        case invalidGoal
        case liveTrackingUnavailable
        case liveStartupFailed(String)
        case immersiveSpaceFailed(String)
    }

    let request: RehabSessionRequest
    let reason: Reason
    let recoveryActions: [SessionRecoveryAction]
}

enum SessionPauseReason: Equatable, Sendable {
    case trackingLost(requiresRecalibration: Bool)
}

enum RehabSessionPhase: Equatable, Sendable {
    case idle
    case starting(RehabSessionRequest)
    case active(
        request: RehabSessionRequest,
        progress: SessionProgress,
        provenance: SessionProvenance
    )
    case paused(
        request: RehabSessionRequest,
        progress: SessionProgress,
        reason: SessionPauseReason
    )
    case failed(SessionFailure)
    case completed(RehabSessionOutcome)
}
