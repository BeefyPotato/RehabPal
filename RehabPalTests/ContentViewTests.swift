import XCTest
@testable import RehabPal

final class ContentViewTests: XCTestCase {
    // Break caught: selecting an exercise opens live tracking before the
    // patient confirms the prescribed dose with Begin.
    func testExercisesRequireBeginBeforeCreatingTheirSessionRequests() {
        for exercise in [ExerciseKind.balance, .squeeze, .sheepDrop] {
            XCTAssertTrue(exercise.requiresExplicitBegin)
            XCTAssertNil(
                ContentView.sessionRequest(
                    for: exercise,
                    hasBegun: false,
                    prescription: .demo
                )
            )
            XCTAssertEqual(
                ContentView.sessionRequest(
                    for: exercise,
                    hasBegun: true,
                    prescription: .demo
                ),
                Prescription.demo.sessionRequest(for: .exercise(exercise))
            )
        }
    }

    // Break caught: cancelling the exercise introduction leaves a request
    // behind that opens an immersive session after returning to the routine.
    func testCancellingExerciseSelectionCreatesNoSessionRequest() {
        XCTAssertNil(
            ContentView.sessionRequest(
                for: nil,
                hasBegun: false,
                prescription: .demo
            )
        )
    }
}
