import Foundation

enum AffectedHand: String, Equatable, Hashable, Sendable {
    case left
    case right
}

struct WristDiagnosticPrescription: Equatable, Sendable {
    let attemptsPerDirection: Int
    let targetDegrees: Float
    let targetToleranceDegrees: Float
    let offAxisToleranceDegrees: Float
    let holdSeconds: TimeInterval
    let neutralReturnToleranceDegrees: Float
}

struct FingerDiagnosticPrescription: Equatable, Sendable {
    let attemptsPerDigit: Int
    let extensionStabilitySeconds: TimeInterval
    let extensionStabilityToleranceDegrees: Float
    let minimumTotalExcursionDegrees: Float
    let extensionReturnToleranceDegrees: Float
    let thumbOppositionReduction: Float
    let thumbOppositionReturnTolerance: Float
}

struct Prescription: Equatable, Sendable {
    let affectedHand: AffectedHand
    let balanceTargetCount: Int
    let squeezeRepetitions: Int
    let sheepDropRepetitions: Int
    let squeezeCloseThreshold: Float
    let squeezeReopenThreshold: Float
    let squeezeHoldSeconds: TimeInterval
    let wristDiagnostic: WristDiagnosticPrescription
    let fingerDiagnostic: FingerDiagnosticPrescription
    let symptomReviewThreshold: Int

    init(
        affectedHand: AffectedHand,
        balanceTargetCount: Int,
        squeezeRepetitions: Int,
        squeezeCloseThreshold: Float,
        squeezeReopenThreshold: Float,
        squeezeHoldSeconds: TimeInterval,
        wristDiagnostic: WristDiagnosticPrescription,
        fingerDiagnostic: FingerDiagnosticPrescription,
        symptomReviewThreshold: Int,
        sheepDropRepetitions: Int = 5
    ) {
        self.affectedHand = affectedHand
        self.balanceTargetCount = balanceTargetCount
        self.squeezeRepetitions = squeezeRepetitions
        self.sheepDropRepetitions = sheepDropRepetitions
        self.squeezeCloseThreshold = squeezeCloseThreshold
        self.squeezeReopenThreshold = squeezeReopenThreshold
        self.squeezeHoldSeconds = squeezeHoldSeconds
        self.wristDiagnostic = wristDiagnostic
        self.fingerDiagnostic = fingerDiagnostic
        self.symptomReviewThreshold = symptomReviewThreshold
    }

    nonisolated static let demo = Prescription(
        affectedHand: .right,
        balanceTargetCount: 10,
        squeezeRepetitions: 5,
        squeezeCloseThreshold: 0.72,
        squeezeReopenThreshold: 0.28,
        squeezeHoldSeconds: 0.7,
        wristDiagnostic: WristDiagnosticPrescription(
            attemptsPerDirection: 2,
            targetDegrees: 20,
            targetToleranceDegrees: 5,
            offAxisToleranceDegrees: 5,
            holdSeconds: 0.5,
            neutralReturnToleranceDegrees: 5
        ),
        fingerDiagnostic: FingerDiagnosticPrescription(
            attemptsPerDigit: 2,
            extensionStabilitySeconds: 0.3,
            extensionStabilityToleranceDegrees: 3,
            minimumTotalExcursionDegrees: 15,
            extensionReturnToleranceDegrees: 8,
            thumbOppositionReduction: 0.25,
            thumbOppositionReturnTolerance: 0.10
        ),
        symptomReviewThreshold: 6,
        sheepDropRepetitions: 5
    )

    func goal(for experience: RehabExperience) -> Int {
        switch experience {
        case .exercise(.balance):
            balanceTargetCount
        case .exercise(.squeeze):
            squeezeRepetitions
        case .exercise(.sheepDrop):
            sheepDropRepetitions
        case .wristAssessment:
            wristDiagnostic.attemptsPerDirection * WristAssessmentTarget.allCases.count
        case .handAssessment:
            fingerDiagnostic.attemptsPerDigit * HandDigit.allCases.count
        }
    }

    func sessionRequest(for experience: RehabExperience) -> RehabSessionRequest {
        RehabSessionRequest(
            experience: experience,
            affectedHand: affectedHand,
            goal: goal(for: experience)
        )
    }
}

enum ExerciseKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case balance
    case squeeze
    case sheepDrop

    var title: String {
        switch self {
        case .balance: "Balance Platform"
        case .squeeze: "Squeeze Buddy"
        case .sheepDrop: "Sheep Drop"
        }
    }

    var systemImage: String {
        switch self {
        case .balance: "circle.grid.cross"
        case .squeeze: "hand.raised.fingers.spread"
        case .sheepDrop: "pawprint.fill"
        }
    }
}
