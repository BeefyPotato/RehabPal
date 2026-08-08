import Foundation

struct BalanceSchedule: Equatable, Sendable {
    let directions: [WristDirection]

    init(correctionsPerDirection: Int, shuffle: Bool = true) {
        let balanced = WristDirection.allCases.flatMap { direction in
            Array(repeating: direction, count: max(0, correctionsPerDirection))
        }
        directions = shuffle ? balanced.shuffled() : balanced
    }
}

struct BalanceSession: Sendable {
    let schedule: BalanceSchedule
    let requiredHoldSeconds: TimeInterval
    private(set) var completedCorrections = 0

    init(correctionsPerDirection: Int, requiredHoldSeconds: TimeInterval, shuffle: Bool = true) {
        schedule = BalanceSchedule(correctionsPerDirection: correctionsPerDirection, shuffle: shuffle)
        self.requiredHoldSeconds = requiredHoldSeconds
    }

    var currentDirection: WristDirection? {
        guard completedCorrections < schedule.directions.count else { return nil }
        return schedule.directions[completedCorrections]
    }

    var isComplete: Bool {
        !schedule.directions.isEmpty && completedCorrections == schedule.directions.count
    }

    var progress: Double {
        guard !schedule.directions.isEmpty else { return 0 }
        return Double(completedCorrections) / Double(schedule.directions.count)
    }

    mutating func registerCentreHold(seconds: TimeInterval, isTracked: Bool) -> Bool {
        guard isTracked, !isComplete, seconds >= requiredHoldSeconds else { return false }
        completedCorrections += 1
        return isComplete
    }
}
