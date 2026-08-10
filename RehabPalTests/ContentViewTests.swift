import XCTest
@testable import RehabPal

final class ContentViewTests: XCTestCase {
    // Break caught: launching Balance before explaining its 25-frame neutral
    // capture and locked viewer-relative placement surprises the user in-space.
    func testBalanceIntroductionExplainsCalibrationAndLockedViewerPlacement() {
        let copy = ExerciseIntroductionCopy.text(
            for: .balance,
            prescription: .demo
        )

        XCTAssertTrue(copy.contains("25 tracking frames"))
        XCTAssertTrue(copy.contains("25 cm below"))
        XCTAssertTrue(copy.contains("locks it there"))
    }

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

    // Mutation caught: a recovery Back action that only clears the coordinator
    // leaves assessment navigation outside Today's Routine.
    @MainActor
    func testReturnToRoutineIntentClearsAuthorizationForExerciseAndDiagnostics() {
        for experience in [
            RehabExperience.exercise(.balance), .wristAssessment, .handAssessment
        ] {
            let state = AppState()
            XCTAssertTrue(state.startRoutine())
            XCTAssertTrue(state.answerMedication(taken: true))
            if experience != .exercise(.balance) {
                XCTAssertTrue(state.startAssessment())
                if experience == .handAssessment {
                    XCTAssertTrue(state.completeWristAssessment(.init(
                        controlScore: 73,
                        trackingConfidence: 1
                    )))
                }
            }
            let request = RehabSessionRequest(experience: experience, prescription: state.prescription)
            XCTAssertTrue(state.activateSession(request, provenance: .live))
            XCTAssertTrue(ContentViewReturnToRoutine.apply(to: state))
            XCTAssertEqual(state.stage, .routine)
            XCTAssertNil(state.activeSession)
        }
    }
}
