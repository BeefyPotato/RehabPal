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
            XCTAssertEqual(state.stage, .wristAssessment)
        }
    }

    @MainActor
    func testAssessmentSymptomsReportAndPetRemainStrictlyOrdered() {
        let state = unlockedRoutine()

        XCTAssertFalse(state.completeWristAssessment(AssessmentResult.fixture.wrist))
        XCTAssertFalse(state.submitSymptoms(.comfortable))
        XCTAssertFalse(state.viewReport())
        XCTAssertFalse(state.feedPet())

        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertTrue(state.completeExercise(.squeeze, result: .fixture(for: .squeeze)))
        XCTAssertTrue(state.completeWristAssessment(AssessmentResult.fixture.wrist))
        XCTAssertEqual(state.stage, .handAssessment)
        XCTAssertTrue(state.completeHandROMAssessment(AssessmentResult.fixture.handROM))
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
    func testHandAssessmentCannotFinishWithMissingDigits() {
        let state = unlockedRoutine()
        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertTrue(state.completeExercise(.squeeze, result: .fixture(for: .squeeze)))
        XCTAssertTrue(state.completeWristAssessment(AssessmentResult.fixture.wrist))
        XCTAssertFalse(state.completeHandROMAssessment([.index: AssessmentResult.fixture.handROM[.index]!]))
        XCTAssertEqual(state.stage, .handAssessment)
    }

    @MainActor
    func testDiagnosticCancelReturnsToRoutineAndRelaunchesThePendingAssessment() {
        let state = unlockedRoutine()
        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertTrue(state.completeExercise(.squeeze, result: .fixture(for: .squeeze)))
        XCTAssertEqual(state.stage, .wristAssessment)

        let wristRequest = RehabSessionRequest(
            experience: .wristAssessment,
            prescription: state.prescription,
            goal: 10
        )
        XCTAssertTrue(state.activateSession(wristRequest, provenance: .live))
        XCTAssertTrue(state.cancelSessionAndReturnToRoutine())
        XCTAssertEqual(state.stage, .routine)
        XCTAssertNil(state.activeSession)
        XCTAssertTrue(state.startAssessment())
        XCTAssertEqual(state.stage, .wristAssessment)

        XCTAssertTrue(state.completeWristAssessment(AssessmentResult.fixture.wrist))
        let handRequest = RehabSessionRequest(
            experience: .handAssessment,
            prescription: state.prescription,
            goal: 10
        )
        XCTAssertTrue(state.activateSession(handRequest, provenance: .demo))
        XCTAssertTrue(state.cancelSessionAndReturnToRoutine())
        XCTAssertEqual(state.stage, .routine)
        XCTAssertNil(state.activeSession)
        XCTAssertTrue(state.startAssessment())
        XCTAssertEqual(state.stage, .handAssessment)
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
    func testEarnedTreatFeedsOnceAndRoutineResetPreservesHunger() {
        let defaults = UserDefaults(suiteName: "AppStateHunger.\(UUID().uuidString)")!
        let now = Date(timeIntervalSince1970: 4_000_000)
        let hunger = PetHungerStore(defaults: defaults, now: now)
        let state = AppState(hunger: hunger)

        completeRoutineThroughReport(state)

        XCTAssertTrue(state.feedPet(at: now))
        XCTAssertFalse(state.feedPet(at: now))
        XCTAssertEqual(hunger.fullness, 70, accuracy: 0.001)

        state.resetDemoDay()

        XCTAssertEqual(hunger.fullness, 70, accuracy: 0.001)
    }

    @MainActor
    private func unlockedRoutine() -> AppState {
        let state = AppState()
        XCTAssertTrue(state.startRoutine())
        XCTAssertTrue(state.answerMedication(taken: true))
        return state
    }

    @MainActor
    private func completeRoutineThroughReport(_ state: AppState) {
        XCTAssertTrue(state.startRoutine())
        XCTAssertTrue(state.answerMedication(taken: true))
        XCTAssertTrue(state.completeExercise(.balance, result: .fixture(for: .balance)))
        XCTAssertTrue(state.completeExercise(.squeeze, result: .fixture(for: .squeeze)))
        XCTAssertTrue(state.completeWristAssessment(AssessmentResult.fixture.wrist))
        XCTAssertTrue(state.completeHandROMAssessment(AssessmentResult.fixture.handROM))
        XCTAssertTrue(state.submitSymptoms(.comfortable))
        XCTAssertTrue(state.viewReport())
    }
}
