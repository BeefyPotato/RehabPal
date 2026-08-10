import Foundation

struct SqueezeRepDetector: Sendable {
    enum Phase: String, Equatable, Sendable {
        case open
        case closing
        case held
        case reopening
    }

    let closeThreshold: Float
    let reopenThreshold: Float
    let holdSeconds: TimeInterval

    private(set) var phase: Phase = .open
    private(set) var completedRepetitions = 0
    private var closedSince: TimeInterval?

    mutating func update(
        closure: Float,
        at timestamp: TimeInterval,
        isTracked: Bool
    ) -> Bool {
        guard isTracked else {
            resetPartial()
            return false
        }

        switch phase {
        case .open:
            guard closure >= closeThreshold else { return false }
            phase = .closing
            closedSince = timestamp
        case .closing:
            guard closure >= closeThreshold else {
                resetPartial()
                return false
            }
            if let closedSince, timestamp - closedSince >= holdSeconds {
                phase = .held
            }
        case .held:
            guard closure < closeThreshold else { return false }
            if closure <= reopenThreshold {
                completeRep()
                return true
            } else {
                phase = .reopening
            }
        case .reopening:
            guard closure <= reopenThreshold else { return false }
            completeRep()
            return true
        }
        return false
    }

    mutating func resetPartial() {
        phase = .open
        closedSince = nil
    }

    private mutating func completeRep() {
        completedRepetitions += 1
        resetPartial()
    }
}
