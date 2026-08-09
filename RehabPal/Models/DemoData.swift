import Foundation

struct DemoHistory: Equatable, Sendable {
    struct ROMSession: Equatable, Sendable, Identifiable {
        let id: UUID
        let date: Date
        let wristScore: Int
        let digitExcursions: [HandDigit: Double]
    }

    let currentStreak: Int
    let completedSessions: Int
    let baselineWristControl: Int
    let previousWristControl: Int
    let baselineClosureConsistency: Int
    let previousClosureConsistency: Int
    let romSessions: [ROMSession]

    nonisolated static let fixture = DemoHistory(
        currentStreak: 4,
        completedSessions: 12,
        baselineWristControl: 61,
        previousWristControl: 69,
        baselineClosureConsistency: 64,
        previousClosureConsistency: 72,
        romSessions: (0..<5).map { offset in
            ROMSession(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(offset)")!,
                date: Calendar.current.date(byAdding: .day, value: -(10 - offset * 2), to: .now)!,
                wristScore: 61 + offset * 3,
                digitExcursions: Dictionary(uniqueKeysWithValues: HandDigit.allCases.map { ($0, Double(72 + offset * 4 + $0.fixtureOffset)) })
            )
        }
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
            prescribedDose: exercise == .balance ? Prescription.demo.balanceTargetCount : 5,
            completedDose: exercise == .balance ? Prescription.demo.balanceTargetCount : 5,
            trackingNote: "Tracking remained usable"
        )
    }
}

struct AssessmentResult: Equatable, Sendable {
    struct WristResult: Equatable, Sendable {
        let controlScore: Int
        let trackingConfidence: Float
    }

    let wrist: WristResult
    let handROM: [HandDigit: DigitROMSummary]

    var wristControlScore: Int { wrist.controlScore }
    var closureConsistencyScore: Int {
        let available = handROM.values.filter(\.isAvailable)
        guard !available.isEmpty else { return 0 }
        return Int(available.map(\.consistency).reduce(0, +) / Double(available.count))
    }
    var trackingConfidence: Float {
        let fingerConfidence = handROM.values.map(\.trackingConfidence)
        guard !fingerConfidence.isEmpty else { return wrist.trackingConfidence }
        return (wrist.trackingConfidence + Float(fingerConfidence.reduce(0, +) / Double(fingerConfidence.count))) / 2
    }

    var availableWristControlScore: Int? {
        wrist.trackingConfidence >= 0.6 ? wrist.controlScore : nil
    }

    var availableClosureConsistencyScore: Int? {
        let available = handROM.values.filter(\.isAvailable)
        guard !available.isEmpty else { return nil }
        return Int(available.map(\.consistency).reduce(0, +) / Double(available.count))
    }

    func availableFingerROM(for digit: HandDigit) -> DigitROMSummary? {
        guard let summary = handROM[digit], summary.isAvailable else { return nil }
        return summary
    }

    func todayTrendValue(for metric: AssessmentTrendMetric) -> Double? {
        switch metric {
        case .wrist:
            availableWristControlScore.map(Double.init)
        case let .finger(digit):
            availableFingerROM(for: digit)?.totalExcursion
        }
    }

    init(wristControlScore: Int, closureConsistencyScore: Int, trackingConfidence: Float) {
        wrist = WristResult(controlScore: wristControlScore, trackingConfidence: trackingConfidence)
        handROM = Dictionary(uniqueKeysWithValues: HandDigit.allCases.map { digit in
            (digit, DigitROMSummary(digit: digit, totalExcursion: Double(closureConsistencyScore), maximumFlexion: Double(closureConsistencyScore), maximumExtension: 0, consistency: Double(closureConsistencyScore), trackingConfidence: Double(trackingConfidence), attemptCount: 2))
        })
    }

    init(wrist: WristResult, handROM: [HandDigit: DigitROMSummary]) {
        self.wrist = wrist
        self.handROM = handROM
    }

    nonisolated static let fixture = AssessmentResult(
        wristControlScore: 73,
        closureConsistencyScore: 76,
        trackingConfidence: 0.92
    )
}

enum AssessmentTrendMetric: Equatable, Sendable {
    case wrist
    case finger(HandDigit)
}

enum HandDigit: String, CaseIterable, Codable, Hashable, Sendable {
    case thumb, index, middle, ring, little

    var title: String { rawValue.capitalized }
    var fixtureOffset: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct FingerROMAttempt: Equatable, Sendable {
    let mcpExcursion: Double
    let pipExcursion: Double
    let dipExcursion: Double
    let maximumFlexion: Double
    let maximumExtension: Double
    let trackingConfidence: Double

    var totalExcursion: Double { mcpExcursion + pipExcursion + dipExcursion }
}

struct DigitROMSummary: Equatable, Sendable {
    let digit: HandDigit
    let totalExcursion: Double
    let maximumFlexion: Double
    let maximumExtension: Double
    let consistency: Double
    let trackingConfidence: Double
    let attemptCount: Int

    var isAvailable: Bool { attemptCount >= 2 && trackingConfidence >= 0.6 }
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
