import Foundation

struct SqueezeRepDetector: Sendable {
    enum Phase: String, Equatable, Sendable {
        case open
        case closing
        case reopening
    }

    let closeThreshold: Float
    let reopenThreshold: Float
    let holdSeconds: TimeInterval

    private(set) var phase: Phase = .open
    private(set) var completedRepetitions = 0
    private var closedSince: TimeInterval?
    private var trackingLostAt: TimeInterval?

    mutating func update(
        closure: Float,
        at timestamp: TimeInterval,
        isTracked: Bool
    ) -> Bool {
        guard isTracked else {
            if trackingLostAt == nil { trackingLostAt = timestamp }
            return false
        }

        if let trackingLostAt {
            if let closedSince {
                self.closedSince = closedSince + max(0, timestamp - trackingLostAt)
            }
            self.trackingLostAt = nil
        }

        switch phase {
        case .open:
            guard closure >= closeThreshold else { return false }
            phase = .closing
            closedSince = timestamp
        case .closing:
            if closure <= reopenThreshold {
                phase = .open
                closedSince = nil
            } else if let closedSince, timestamp - closedSince >= holdSeconds {
                phase = .reopening
            }
        case .reopening:
            guard closure <= reopenThreshold else { return false }
            completedRepetitions += 1
            phase = .open
            closedSince = nil
            return true
        }
        return false
    }
}
