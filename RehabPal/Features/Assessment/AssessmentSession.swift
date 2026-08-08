import Foundation

struct AssessmentProtocol: Equatable, Sendable {
    let wristAttemptsPerDirection: Int
    let squeezeRepetitions: Int
    let wristTolerance: Float
    let closeSeconds: TimeInterval = 2
    let holdSeconds: TimeInterval = 1
    let releaseSeconds: TimeInterval = 2
    let isAdaptive = false

    init(prescription: Prescription) {
        wristAttemptsPerDirection = prescription.assessmentAttemptsPerDirection
        squeezeRepetitions = prescription.assessmentSqueezeRepetitions
        wristTolerance = 0.06
    }
}

struct GameplayTolerance: Equatable, Sendable {
    let wristTolerance: Float
    let isAdaptive = true

    init(prescription: Prescription) {
        wristTolerance = max(0.1, prescription.balanceCentreTolerance)
    }
}

struct AssessmentSession: Sendable {
    let protocolSettings: AssessmentProtocol
    private(set) var wristScores: [Int] = []
    private(set) var closureScores: [Int] = []
    private(set) var trackedSamples = 0
    private(set) var totalSamples = 0

    init(prescription: Prescription) {
        protocolSettings = AssessmentProtocol(prescription: prescription)
    }

    mutating func recordWristAttempt(score: Int, isTracked: Bool) {
        totalSamples += 1
        guard isTracked else { return }
        trackedSamples += 1
        wristScores.append(min(max(score, 0), 100))
    }

    mutating func recordClosureRepetition(score: Int, isTracked: Bool) {
        totalSamples += 1
        guard isTracked else { return }
        trackedSamples += 1
        closureScores.append(min(max(score, 0), 100))
    }

    func result() -> AssessmentResult {
        AssessmentResult(
            wristControlScore: average(wristScores),
            closureConsistencyScore: average(closureScores),
            trackingConfidence: totalSamples == 0 ? 0 : Float(trackedSamples) / Float(totalSamples)
        )
    }

    private func average(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }
}
