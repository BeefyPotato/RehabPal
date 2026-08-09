import Foundation
import Observation

@MainActor
@Observable
final class PetHungerStore {
    static let dailyLoss = 15.0
    static let treatGain = 20.0
    private static let fullnessKey = "rehabPal.petFullness"
    private static let updatedAtKey = "rehabPal.petFullnessUpdatedAt"
    private let defaults: UserDefaults
    private(set) var fullness: Double
    private var updatedAt: Date

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        if defaults.object(forKey: Self.updatedAtKey) == nil {
            fullness = 50
            updatedAt = now
            persist()
        } else {
            fullness = min(max(defaults.double(forKey: Self.fullnessKey), 0), 100)
            updatedAt = Date(timeIntervalSince1970: defaults.double(forKey: Self.updatedAtKey))
            resolve(at: now)
        }
    }

    func resolve(at date: Date) {
        guard date >= updatedAt else { updatedAt = date; persist(); return }
        fullness = min(max(fullness - date.timeIntervalSince(updatedAt) / 86_400 * Self.dailyLoss, 0), 100)
        updatedAt = date
        persist()
    }

    func feed(at date: Date = .now) {
        resolve(at: date)
        fullness = min(fullness + Self.treatGain, 100)
        persist()
    }

    func simulateDayPassing(at date: Date = .now) {
        updatedAt = updatedAt.addingTimeInterval(-86_400)
        resolve(at: date)
    }

    private func persist() {
        defaults.set(fullness, forKey: Self.fullnessKey)
        defaults.set(updatedAt.timeIntervalSince1970, forKey: Self.updatedAtKey)
    }
}
