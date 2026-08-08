import XCTest
@testable import RehabPal

final class AppStateTests: XCTestCase {
    @MainActor
    func testMedicationNoKeepsRoutineLockedThenYesUnlocksIt() {
        let state = AppState()

        XCTAssertTrue(state.startRoutine())
        XCTAssertEqual(state.stage, .medicationGate)
        XCTAssertFalse(state.answerMedication(taken: false))
        XCTAssertEqual(state.stage, .medicationGate)
        XCTAssertFalse(state.canStartExercises)

        XCTAssertTrue(state.answerMedication(taken: true))
        XCTAssertEqual(state.stage, .routine)
        XCTAssertTrue(state.canStartExercises)
    }

    @MainActor
    func testBothExerciseOrdersUnlockAssessmentOnlyAfterSecondCompletion() {
        for order in [[ExerciseKind.balance, .squeeze], [.squeeze, .balance]] {
            let state = unlockedRoutine()

            XCTAssertTrue(state.completeExercise(order[0], result: .fixture(for: order[0])))
            XCTAssertFalse(state.canStartAssessment)
            XCTAssertEqual(state.stage, .routine)

            XCTAssertTrue(state.completeExercise(order[1], result: .fixture(for: order[1])))
            XCTAssertTrue(state.canStartAssessment)
            XCTAssertEqual(state.stage, .assessment)
        }
    }

    @MainActor
    func testAssessmentSymptomsReportAndPetRemainStrictlyOrdered() {
        let state = unlockedRoutine()

        XCTAssertFalse(state.completeAssessment(.fixture))
        XCTAssertFalse(state.submitSymptoms(.comfortable))
        XCTAssertFalse(state.viewReport())
        XCTAssertFalse(state.feedPet())

        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertTrue(state.completeExercise(.squeeze, result: .fixture(for: .squeeze)))
        XCTAssertTrue(state.completeAssessment(.fixture))
        XCTAssertEqual(state.stage, .symptomCheck)
        XCTAssertTrue(state.submitSymptoms(.comfortable))
        XCTAssertEqual(state.stage, .report)
        XCTAssertTrue(state.viewReport())
        XCTAssertEqual(state.stage, .petReward)
        XCTAssertTrue(state.feedPet())
        XCTAssertEqual(state.stage, .complete)
        XCTAssertTrue(state.petIsFull)
        XCTAssertFalse(state.feedPet())
    }

    @MainActor
    func testDuplicateExerciseCompletionCannotCreateExtraReward() {
        let state = unlockedRoutine()
        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertFalse(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertEqual(state.completedExercises, [.balance])
        XCTAssertFalse(state.canStartAssessment)
    }

    @MainActor
    func testResetClearsTodayAndPreservesPrescriptionAndHistory() {
        let state = unlockedRoutine()
        let prescription = state.prescription
        let history = state.history
        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))

        state.resetDemoDay()

        XCTAssertEqual(state.stage, .home)
        XCTAssertTrue(state.completedExercises.isEmpty)
        XCTAssertNil(state.assessmentResult)
        XCTAssertNil(state.symptomResult)
        XCTAssertFalse(state.reportViewed)
        XCTAssertFalse(state.petIsFull)
        XCTAssertEqual(state.prescription, prescription)
        XCTAssertEqual(state.history, history)
    }

    @MainActor
    private func unlockedRoutine() -> AppState {
        let state = AppState()
        XCTAssertTrue(state.startRoutine())
        XCTAssertTrue(state.answerMedication(taken: true))
        return state
    }
}
