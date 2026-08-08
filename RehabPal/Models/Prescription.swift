import Foundation

enum AffectedHand: String, Equatable, Sendable {
    case left
    case right
}

struct Prescription: Equatable, Sendable {
    let affectedHand: AffectedHand
    let balanceCorrectionsPerDirection: Int
    let balanceCentreTolerance: Float
    let balanceHoldSeconds: TimeInterval
    let squeezeRepetitions: Int
    let squeezeCloseThreshold: Float
    let squeezeReopenThreshold: Float
    let squeezeHoldSeconds: TimeInterval
    let assessmentAttemptsPerDirection: Int
    let assessmentSqueezeRepetitions: Int
    let symptomReviewThreshold: Int

    nonisolated static let demo = Prescription(
        affectedHand: .right,
        balanceCorrectionsPerDirection: 1,
        balanceCentreTolerance: 0.16,
        balanceHoldSeconds: 0.8,
        squeezeRepetitions: 5,
        squeezeCloseThreshold: 0.72,
        squeezeReopenThreshold: 0.28,
        squeezeHoldSeconds: 0.7,
        assessmentAttemptsPerDirection: 2,
        assessmentSqueezeRepetitions: 5,
        symptomReviewThreshold: 6
    )
}

enum ExerciseKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case balance
    case squeeze

    var title: String {
        switch self {
        case .balance: "Balance Platform"
        case .squeeze: "Squeeze Buddy"
        }
    }
}
