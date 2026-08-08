import Foundation

struct DemoHistory: Equatable, Sendable {
    let currentStreak: Int
    let completedSessions: Int
    let baselineWristControl: Int
    let previousWristControl: Int
    let baselineClosureConsistency: Int
    let previousClosureConsistency: Int

    nonisolated static let fixture = DemoHistory(
        currentStreak: 4,
        completedSessions: 12,
        baselineWristControl: 61,
        previousWristControl: 69,
        baselineClosureConsistency: 64,
        previousClosureConsistency: 72
    )
}

struct GameplayResult: Equatable, Sendable {
    let exercise: ExerciseKind
    let prescribedDose: Int
    let completedDose: Int
    let trackingNote: String

    nonisolated static func fixture(for exercise: ExerciseKind) -> GameplayResult {
        GameplayResult(
            exercise: exercise,
            prescribedDose: exercise == .balance ? 4 : 5,
            completedDose: exercise == .balance ? 4 : 5,
            trackingNote: "Tracking remained usable"
        )
    }
}

struct AssessmentResult: Equatable, Sendable {
    let wristControlScore: Int
    let closureConsistencyScore: Int
    let trackingConfidence: Float

    nonisolated static let fixture = AssessmentResult(
        wristControlScore: 73,
        closureConsistencyScore: 76,
        trackingConfidence: 0.92
    )
}

struct SymptomResult: Equatable, Sendable {
    let discomfort: Int
    let increasedSinceStart: Bool
    let stiffness: Int
    let difficulty: Int
    let catchingOrLocking: Bool

    nonisolated static let comfortable = SymptomResult(
        discomfort: 2,
        increasedSinceStart: false,
        stiffness: 3,
        difficulty: 2,
        catchingOrLocking: false
    )
}
