import XCTest
@testable import RehabPal

final class DemoRouterTests: XCTestCase {
    @MainActor
    func testRouterDerivesScreensOnlyFromGuardedAppState() {
        let state = AppState()
        XCTAssertEqual(DemoRouter.screen(for: state), .home)
        XCTAssertTrue(state.startRoutine())
        XCTAssertEqual(DemoRouter.screen(for: state), .medication)
        XCTAssertTrue(state.answerMedication(taken: true))
        XCTAssertEqual(DemoRouter.screen(for: state), .routine)
        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertTrue(state.completeExercise(.squeeze, result: .fixture(for: .squeeze)))
        XCTAssertTrue(state.completeExercise(.sheepDrop, result: .fixture(for: .sheepDrop)))
        XCTAssertEqual(DemoRouter.screen(for: state), .wristAssessment)
    }
}
