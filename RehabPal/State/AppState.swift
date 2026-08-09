import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Stage: Equatable {
        case home
        case medicationGate
        case routine
        case wristAssessment
        case handAssessment
        case symptomCheck
        case report
        case petReward
        case complete
    }

    let prescription: Prescription
    let history: DemoHistory
    let hunger: PetHungerStore

    private(set) var stage: Stage = .home
    private(set) var medicationConfirmed = false
    private(set) var exerciseResults: [ExerciseKind: GameplayResult] = [:]
    private(set) var sessionOutcomes: [RehabExperience: RehabSessionOutcome] = [:]
    private(set) var assessmentResult: AssessmentResult?
    private var wristAssessment: AssessmentResult.WristResult?
    private(set) var symptomResult: SymptomResult?
    private(set) var reportViewed = false
    private(set) var petIsFull = false

    init(
        prescription: Prescription = .demo,
        history: DemoHistory = .fixture,
        hunger: PetHungerStore? = nil
    ) {
        self.prescription = prescription
        self.history = history
        self.hunger = hunger ?? PetHungerStore()
    }

    var completedExercises: Set<ExerciseKind> {
        Set(exerciseResults.keys)
    }

    var canStartExercises: Bool {
        stage == .routine && medicationConfirmed
    }

    var canStartAssessment: Bool {
        completedExercises == Set(ExerciseKind.allCases)
    }

    @discardableResult
    func startRoutine() -> Bool {
        guard stage == .home else { return false }
        stage = .medicationGate
        return true
    }

    @discardableResult
    func answerMedication(taken: Bool) -> Bool {
        guard stage == .medicationGate else { return false }
        medicationConfirmed = taken
        guard taken else { return false }
        stage = .routine
        return true
    }

    @discardableResult
    func completeExercise(_ exercise: ExerciseKind, result: GameplayResult) -> Bool {
        guard canStartExercises, result.exercise == exercise, exerciseResults[exercise] == nil else {
            return false
        }
        exerciseResults[exercise] = result
        if canStartAssessment {
            stage = .wristAssessment
        }
        return true
    }

    @discardableResult
    func route(_ outcome: RehabSessionOutcome) -> Bool {
        guard outcome.request.affectedHand == prescription.affectedHand,
              outcome.progress.completed == outcome.progress.goal,
              outcome.progress.goal == outcome.request.goal,
              sessionOutcomes[outcome.request.experience] == nil else {
            return false
        }

        let accepted: Bool
        switch (outcome.request.experience, outcome.payload) {
        case let (.exercise(exercise), .gameplay(result)):
            accepted = completeExercise(exercise, result: result)
        case let (.wristAssessment, .wristAssessment(result)):
            accepted = completeWristAssessment(result)
        case let (.handAssessment, .handAssessment(result)):
            accepted = completeHandROMAssessment(result)
        default:
            accepted = false
        }
        if accepted {
            sessionOutcomes[outcome.request.experience] = outcome
        }
        return accepted
    }

    @discardableResult
    func completeWristAssessment(_ result: AssessmentResult.WristResult) -> Bool {
        guard stage == .wristAssessment, canStartAssessment else { return false }
        wristAssessment = result
        stage = .handAssessment
        return true
    }

    @discardableResult
    func completeHandROMAssessment(_ result: [HandDigit: DigitROMSummary]) -> Bool {
        guard stage == .handAssessment, let wristAssessment else { return false }
        guard Set(result.keys) == Set(HandDigit.allCases) else { return false }
        assessmentResult = AssessmentResult(wrist: wristAssessment, handROM: result)
        stage = .symptomCheck
        return true
    }

    @discardableResult
    func submitSymptoms(_ result: SymptomResult) -> Bool {
        guard stage == .symptomCheck, assessmentResult != nil else { return false }
        symptomResult = result
        stage = .report
        return true
    }

    @discardableResult
    func viewReport() -> Bool {
        guard stage == .report, symptomResult != nil else { return false }
        reportViewed = true
        stage = .petReward
        return true
    }

    @discardableResult
    func feedPet(at date: Date = .now) -> Bool {
        guard stage == .petReward, reportViewed, !petIsFull else { return false }
        hunger.feed(at: date)
        petIsFull = true
        stage = .complete
        return true
    }

    func resolvePetHunger(at date: Date = .now) {
        hunger.resolve(at: date)
    }

    func simulatePetDay(at date: Date = .now) {
        hunger.simulateDayPassing(at: date)
    }

    func resetDemoDay() {
        stage = .home
        medicationConfirmed = false
        exerciseResults.removeAll()
        sessionOutcomes.removeAll()
        assessmentResult = nil
        wristAssessment = nil
        symptomResult = nil
        reportViewed = false
        petIsFull = false
    }
}
