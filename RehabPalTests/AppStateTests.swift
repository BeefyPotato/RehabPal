import XCTest
@testable import RehabPal

final class AppStateTests: XCTestCase {
    @MainActor
    func testNewDemoDayStartsAtHome() {
        let state = AppState()
        XCTAssertEqual(state.stage, .home)
    }
}
