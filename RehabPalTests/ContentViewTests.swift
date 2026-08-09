import XCTest
@testable import RehabPal

final class ContentViewTests: XCTestCase {
    // Break caught: a new exercise with a visible Begin action can start live
    // tracking before the patient explicitly begins its prescribed dose.
    func testSqueezeAndSheepDropRequireBeginBeforeCreatingTheirSessionRequests() {
        for exercise in [ExerciseKind.squeeze, .sheepDrop] {
            XCTAssertFalse(ContentView.beginsRoutineExerciseImmediately(exercise))
            XCTAssertNil(
                ContentView.routineExerciseRequest(
                    for: exercise,
                    hasBegun: false,
                    prescription: .demo
                )
            )
            XCTAssertEqual(
                ContentView.routineExerciseRequest(
                    for: exercise,
                    hasBegun: true,
                    prescription: .demo
                ),
                Prescription.demo.sessionRequest(for: .exercise(exercise))
            )
        }
    }

    func testBalanceCreatesItsSessionRequestWithoutAnExplicitBeginAction() {
        XCTAssertTrue(ContentView.beginsRoutineExerciseImmediately(.balance))
        XCTAssertEqual(
            ContentView.routineExerciseRequest(
                for: .balance,
                hasBegun: false,
                prescription: .demo
            ),
            Prescription.demo.sessionRequest(for: .exercise(.balance))
        )
    }
}
