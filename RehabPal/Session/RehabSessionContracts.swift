import Foundation

enum LiveHandJointSessionEvent: Equatable, Sendable {
    case interrupted
    case authorizationDenied
    case providerFailed(String)
}

@MainActor
protocol LiveHandJointSession: AnyObject {
    var isSupported: Bool { get }
    var latestJointFrame: HandJointFrame? { get }
    var viewerPosition: SIMD3<Float>? { get }
    var tablePlacement: TablePlacement? { get }
    func start() async throws
    func stop()
    func jointFrame(for hand: AffectedHand) -> HandJointFrame?
    func setEventHandler(
        _ handler: @escaping (LiveHandJointSessionEvent, TimeInterval) -> Void
    )
}

extension LiveHandJointSession {
    var viewerPosition: SIMD3<Float>? { nil }
    var tablePlacement: TablePlacement? { nil }

    func jointFrame(for hand: AffectedHand) -> HandJointFrame? {
        guard latestJointFrame?.hand == hand else { return nil }
        return latestJointFrame
    }

    func setEventHandler(
        _: @escaping (LiveHandJointSessionEvent, TimeInterval) -> Void
    ) {}
}

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
    static let minimumDiagnosticAttemptsPerSubject = 2

    var hasValidGoal: Bool {
        guard goal > 0 else { return false }
        switch experience {
        case .exercise:
            return true
        case .wristAssessment, .handAssessment:
            return goal.isMultiple(of: Self.diagnosticSubjectCount) &&
            goal / Self.diagnosticSubjectCount >= Self.minimumDiagnosticAttemptsPerSubject
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
    let assistedProgressCount: Int

    init(
        request: RehabSessionRequest,
        progress: SessionProgress,
        provenance: SessionProvenance,
        payload: SessionOutcomePayload,
        assistedProgressCount: Int = 0
    ) {
        self.request = request
        self.progress = progress
        self.provenance = provenance
        self.payload = payload
        self.assistedProgressCount = max(0, assistedProgressCount)
    }
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
        case liveAuthorizationDenied
        case liveProviderFailed(String)
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

enum AssistedProgressControl {
    static let title = "Complete Current Step (Assisted)"

    static func isAuthorized(
        _ phase: RehabSessionPhase,
        for experience: RehabExperience
    ) -> Bool {
        switch phase {
        case let .active(request, progress, _), let .paused(request, progress, _):
            return request.experience == experience && progress.completed < progress.goal
        case .idle, .starting, .failed, .completed:
            return false
        }
    }
}
