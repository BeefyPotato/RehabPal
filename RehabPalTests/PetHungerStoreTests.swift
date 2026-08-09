import XCTest
@testable import RehabPal

final class PetHungerStoreTests: XCTestCase {
    @MainActor
    func testFreshStoreStartsHalfFullAndLosesFifteenPointsPerDay() {
        let defaults = isolatedDefaults()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let store = PetHungerStore(defaults: defaults, now: start)
        XCTAssertEqual(store.fullness, 50, accuracy: 0.001)
        store.resolve(at: start.addingTimeInterval(43_200))
        XCTAssertEqual(store.fullness, 42.5, accuracy: 0.001)
        store.resolve(at: start.addingTimeInterval(86_400))
        XCTAssertEqual(store.fullness, 35, accuracy: 0.001)
    }

    @MainActor
    func testFeedResolvesLossThenAddsTwentyAndClamps() {
        let defaults = isolatedDefaults()
        let start = Date(timeIntervalSince1970: 2_000_000)
        let store = PetHungerStore(defaults: defaults, now: start)
        store.feed(at: start.addingTimeInterval(86_400))
        XCTAssertEqual(store.fullness, 55, accuracy: 0.001)
        store.feed(at: start.addingTimeInterval(86_401))
        store.feed(at: start.addingTimeInterval(86_402))
        store.feed(at: start.addingTimeInterval(86_403))
        XCTAssertEqual(store.fullness, 100, accuracy: 0.001)
    }

    @MainActor
    func testPersistenceClampAndBackwardClock() {
        let defaults = isolatedDefaults()
        let start = Date(timeIntervalSince1970: 3_000_000)
        let first = PetHungerStore(defaults: defaults, now: start)
        first.resolve(at: start.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(first.fullness, 0, accuracy: 0.001)
        let reloaded = PetHungerStore(defaults: defaults, now: start.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(reloaded.fullness, 0, accuracy: 0.001)
        reloaded.resolve(at: start)
        XCTAssertEqual(reloaded.fullness, 0, accuracy: 0.001)
    }

    @MainActor
    func testSimulatedDaySubtractsExactlyDailyLoss() {
        let defaults = isolatedDefaults()
        let start = Date(timeIntervalSince1970: 3_500_000)
        let store = PetHungerStore(defaults: defaults, now: start)
        store.simulateDayPassing(at: start)
        XCTAssertEqual(store.fullness, 35, accuracy: 0.001)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "PetHungerStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
