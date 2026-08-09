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

    init(experience: RehabExperience, prescription: Prescription) {
        self = prescription.sessionRequest(for: experience)
    }

    init(experience: RehabExperience, affectedHand: AffectedHand, goal: Int) {
        self.experience = experience
        self.affectedHand = affectedHand
        self.goal = goal
    }
}

extension RehabSessionRequest {
    static let diagnosticSubjectCount = 5

    var hasValidGoal: Bool {
        guard goal > 0 else { return false }
        switch experience {
        case .exercise:
            return true
        case .wristAssessment, .handAssessment:
            return goal.isMultiple(of: Self.diagnosticSubjectCount)
        }
    }

    var diagnosticAttemptsPerSubject: Int? {
        guard hasValidGoal else { return nil }
        switch experience {
        case .wristAssessment, .handAssessment:
            return goal / Self.diagnosticSubjectCount
        case .exercise:
            return nil
        }
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

extension SessionOutcomePayload {
    func matches(_ request: RehabSessionRequest) -> Bool {
        switch (request.experience, self) {
        case let (.exercise(exercise), .gameplay(result)):
            result.exercise == exercise &&
            result.prescribedDose == request.goal &&
            result.completedDose == request.goal
        case (.wristAssessment, .wristAssessment):
            true
        case let (.handAssessment, .handAssessment(result)):
            Set(result.keys) == Set(HandDigit.allCases) &&
            result.values.allSatisfy {
                $0.attemptCount == request.diagnosticAttemptsPerSubject
            }
        default:
            false
        }
    }
}

struct RehabSessionOutcome: Equatable, Sendable {
    let request: RehabSessionRequest
    let progress: SessionProgress
    let provenance: SessionProvenance
    let payload: SessionOutcomePayload
}

struct ActiveRehabSession: Equatable, Sendable {
    let request: RehabSessionRequest
    let provenance: SessionProvenance
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
