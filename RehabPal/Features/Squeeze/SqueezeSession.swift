import Foundation

struct SqueezeSession: Sendable {
    let prescribedRepetitions: Int
    private var detector: SqueezeRepDetector

    init(
        repetitions: Int,
        closeThreshold: Float,
        reopenThreshold: Float,
        holdSeconds: TimeInterval
    ) {
        prescribedRepetitions = repetitions
        detector = SqueezeRepDetector(
            closeThreshold: closeThreshold,
            reopenThreshold: reopenThreshold,
            holdSeconds: holdSeconds
        )
    }

    var completedRepetitions: Int { detector.completedRepetitions }
    var phase: SqueezeRepDetector.Phase { detector.phase }
    var isComplete: Bool { completedRepetitions >= prescribedRepetitions }

    mutating func update(closure: Float, at timestamp: TimeInterval, isTracked: Bool) -> Bool {
        guard !isComplete else { return false }
        let completedRep = detector.update(closure: closure, at: timestamp, isTracked: isTracked)
        return completedRep && isComplete
    }
}
