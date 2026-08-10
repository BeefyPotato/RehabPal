import Foundation
import simd

struct HandROMAssessmentSession: Sendable {
    let attemptsPerDigit: Int
    private(set) var attempts: [HandDigit: [FingerROMAttempt]] = [:]

    init(attemptsPerDigit: Int = 2) {
        self.attemptsPerDigit = attemptsPerDigit
    }

    mutating func record(_ attempt: FingerROMAttempt, for digit: HandDigit) -> Bool {
        var digitAttempts = attempts[digit, default: []]
        guard digitAttempts.count < attemptsPerDigit else { return true }
        digitAttempts.append(attempt)
        attempts[digit] = digitAttempts
        return digitAttempts.count == attemptsPerDigit
    }

    func summary(for digit: HandDigit) -> DigitROMSummary? {
        guard let values = attempts[digit], !values.isEmpty else { return nil }
        func mean(_ keyPath: KeyPath<FingerROMAttempt, Double>) -> Double {
            values.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(values.count)
        }
        let totals = values.map(\.totalExcursion)
        let spread = (totals.max() ?? 0) - (totals.min() ?? 0)
        return DigitROMSummary(
            digit: digit,
            totalExcursion: totals.reduce(0, +) / Double(values.count),
            maximumFlexion: mean(\.maximumFlexion),
            maximumExtension: mean(\.maximumExtension),
            consistency: max(0, 100 - spread),
            trackingConfidence: mean(\.trackingConfidence),
            attemptCount: values.count
        )
    }
}

struct FingerROMCaptureAccumulator: Sendable {
    private var minimumAngles: SIMD3<Float>?
    private var maximumAngles: SIMD3<Float>?

    mutating func record(_ angles: SIMD3<Float>) {
        guard angles.x.isFinite, angles.y.isFinite, angles.z.isFinite else { return }
        if let minimumAngles, let maximumAngles {
            self.minimumAngles = simd.min(minimumAngles, angles)
            self.maximumAngles = simd.max(maximumAngles, angles)
        } else {
            minimumAngles = angles
            maximumAngles = angles
        }
    }

    mutating func finish(trackingConfidence: Double) -> FingerROMAttempt? {
        defer {
            minimumAngles = nil
            maximumAngles = nil
        }
        guard trackingConfidence.isFinite,
              let minimumAngles,
              let maximumAngles else { return nil }

        let excursion = maximumAngles - minimumAngles
        guard excursion.x.isFinite, excursion.y.isFinite, excursion.z.isFinite else { return nil }

        return FingerROMAttempt(
            mcpExcursion: Double(excursion.x),
            pipExcursion: Double(excursion.y),
            dipExcursion: Double(excursion.z),
            maximumFlexion: Double(maximumAngles.max()),
            maximumExtension: Double(minimumAngles.min()),
            trackingConfidence: trackingConfidence
        )
    }
}
