import Foundation
import simd

enum BalanceQuadrant: CaseIterable, Equatable, Sendable {
    case frontLeft, frontRight, backLeft, backRight
}

struct BalanceTarget: Equatable, Sendable {
    let x: Float
    let z: Float
    let quadrant: BalanceQuadrant
    var position: SIMD2<Float> { [x, z] }
}

struct BalanceTargetSchedule: Equatable, Sendable {
    let targets: [BalanceTarget]

    init(seed: UInt64) {
        let positions: [BalanceQuadrant: [(Float, Float)]] = [
            .frontLeft: [(-0.17, -0.10), (-0.09, -0.055)],
            .frontRight: [(0.17, -0.10), (0.09, -0.055)],
            .backLeft: [(-0.17, 0.10), (-0.09, 0.055)],
            .backRight: [(0.17, 0.10), (0.09, 0.055)]
        ]
        var rng = SeededGenerator(seed: seed)
        var remaining = Dictionary(uniqueKeysWithValues: BalanceQuadrant.allCases.map { ($0, positions[$0]!.shuffled(using: &rng)) })
        var order: [BalanceQuadrant] = []
        while order.count < 8 {
            var choices = BalanceQuadrant.allCases.filter { remaining[$0]?.isEmpty == false && $0 != order.last }
            choices.shuffle(using: &rng)
            let selected = choices[0]
            order.append(selected)
            _ = remaining[selected]?.removeLast()
        }
        var indices = Dictionary(uniqueKeysWithValues: BalanceQuadrant.allCases.map { ($0, 0) })
        targets = order.map { quadrant in
            let pair = positions[quadrant]![indices[quadrant, default: 0]]
            indices[quadrant, default: 0] += 1
            return BalanceTarget(x: pair.0, z: pair.1, quadrant: quadrant)
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

struct MovingHoleBalanceSession: Sendable {
    let schedule: BalanceTargetSchedule
    let requiredRepetitions: Int
    let dwellSeconds: TimeInterval
    private(set) var completedRepetitions = 0
    private var enteredAt: TimeInterval?

    init(seed: UInt64, requiredRepetitions: Int = 8, dwellSeconds: TimeInterval = 0.5) {
        schedule = BalanceTargetSchedule(seed: seed)
        self.requiredRepetitions = min(max(requiredRepetitions, 1), schedule.targets.count)
        self.dwellSeconds = dwellSeconds
    }

    var currentTarget: BalanceTarget { schedule.targets[min(completedRepetitions, schedule.targets.count - 1)] }
    var progress: Double { Double(completedRepetitions) / Double(requiredRepetitions) }
    var isComplete: Bool { completedRepetitions >= requiredRepetitions }

    mutating func update(ballPosition: SIMD2<Float>, at time: TimeInterval, isTracked: Bool) -> Bool {
        guard !isComplete else { return true }
        guard isTracked else { enteredAt = nil; return false }
        guard simd_distance(ballPosition, currentTarget.position) <= 0.055 else { enteredAt = nil; return false }
        if enteredAt == nil { enteredAt = time; return false }
        guard time - enteredAt! >= dwellSeconds else { return false }
        completedRepetitions += 1
        enteredAt = nil
        return isComplete
    }
}

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
