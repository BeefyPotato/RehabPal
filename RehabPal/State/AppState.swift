import Observation

@MainActor
@Observable
final class AppState {
    enum Stage: Equatable {
        case home
        case medicationGate
        case routine
        case assessment
        case symptomCheck
        case report
        case petReward
        case complete
    }

    let prescription: Prescription
    let history: DemoHistory

    private(set) var stage: Stage = .home
    private(set) var medicationConfirmed = false
    private(set) var exerciseResults: [ExerciseKind: GameplayResult] = [:]
    private(set) var assessmentResult: AssessmentResult?
    private(set) var symptomResult: SymptomResult?
    private(set) var reportViewed = false
    private(set) var petIsFull = false

    init(
        prescription: Prescription = .demo,
        history: DemoHistory = .fixture
    ) {
        self.prescription = prescription
        self.history = history
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
            stage = .assessment
        }
        return true
    }

    @discardableResult
    func completeAssessment(_ result: AssessmentResult) -> Bool {
        guard stage == .assessment, canStartAssessment else { return false }
        assessmentResult = result
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
    func feedPet() -> Bool {
        guard stage == .petReward, reportViewed, !petIsFull else { return false }
        petIsFull = true
        stage = .complete
        return true
    }

    func resetDemoDay() {
        stage = .home
        medicationConfirmed = false
        exerciseResults.removeAll()
        assessmentResult = nil
        symptomResult = nil
        reportViewed = false
        petIsFull = false
    }
}
