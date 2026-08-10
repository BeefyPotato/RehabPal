import Foundation

struct AfterCareReport: Equatable, Sendable {
    struct AssessmentSection: Equatable, Sendable {
        let baselineWristControl: Int
        let previousWristControl: Int
        let currentWristControl: Int?
        let baselineClosureConsistency: Int
        let previousClosureConsistency: Int
        let currentClosureConsistency: Int?
        let trackingNote: String
    }

    struct GameplaySection: Equatable, Sendable {
        let completedExercises: Int
        let completedDose: Int
        let prescribedDose: Int
        let trackingNotes: [String]
    }

    struct PatientReportedSection: Equatable, Sendable {
        let discomfort: Int
        let stiffness: Int
        let difficulty: Int
        let increasedSinceStart: Bool
        let reviewWithPhysiotherapist: Bool
    }

    let assessment: AssessmentSection
    let gameplay: GameplaySection
    let patientReported: PatientReportedSection
    let streak: Int
    let simulatedResultLabels: [String]
    let assistedResultLabels: [String]

    var simulationNote: String? {
        guard !simulatedResultLabels.isEmpty else { return nil }
        return "SIMULATED DEMO RESULTS — \(simulatedResultLabels.joined(separator: ", "))"
    }

    var assistedProgressNote: String? {
        guard !assistedResultLabels.isEmpty else { return nil }
        return "ASSISTED PROGRESS — NOT FULLY HAND-TRACKED: \(assistedResultLabels.joined(separator: ", "))"
    }

    @MainActor
    static func make(
        history: DemoHistory,
        assessment: AssessmentResult,
        gameplay: [GameplayResult],
        symptoms: SymptomResult,
        reviewThreshold: Int,
        sessionProvenance: [RehabExperience: SessionProvenance],
        assistedProgressCounts: [RehabExperience: Int]? = nil
    ) -> AfterCareReport {
        let currentWristControl = assessment.availableWristControlScore
        let currentClosureConsistency = assessment.availableClosureConsistencyScore
        let trackingNote: String
        switch (currentWristControl, currentClosureConsistency) {
        case (.some, .some):
            trackingNote = "Tracking confidence was sufficient for available comparisons"
        case (.some, .none):
            trackingNote = "Wrist comparison available; finger comparison unavailable"
        case (.none, .some):
            trackingNote = "Wrist comparison unavailable; available fingers are shown"
        case (.none, .none):
            trackingNote = "Low tracking confidence—comparison unavailable"
        }
        let resultOrder: [(RehabExperience, String)] = [
            (.exercise(.balance), ExerciseKind.balance.title),
            (.exercise(.squeeze), ExerciseKind.squeeze.title),
            (.exercise(.sheepDrop), ExerciseKind.sheepDrop.title),
            (.wristAssessment, "Wrist assessment"),
            (.handAssessment, "Hand ROM assessment")
        ]
        return AfterCareReport(
            assessment: AssessmentSection(
                baselineWristControl: history.baselineWristControl,
                previousWristControl: history.previousWristControl,
                currentWristControl: currentWristControl,
                baselineClosureConsistency: history.baselineClosureConsistency,
                previousClosureConsistency: history.previousClosureConsistency,
                currentClosureConsistency: currentClosureConsistency,
                trackingNote: trackingNote
            ),
            gameplay: GameplaySection(
                completedExercises: gameplay.filter { $0.completedDose >= $0.prescribedDose }.count,
                completedDose: gameplay.reduce(0) { $0 + $1.completedDose },
                prescribedDose: gameplay.reduce(0) { $0 + $1.prescribedDose },
                trackingNotes: gameplay.map(\.trackingNote).sorted()
            ),
            patientReported: PatientReportedSection(
                discomfort: symptoms.discomfort,
                stiffness: symptoms.stiffness,
                difficulty: symptoms.difficulty,
                increasedSinceStart: symptoms.increasedSinceStart,
                reviewWithPhysiotherapist: SymptomEvaluator(reviewThreshold: reviewThreshold)
                    .needsPhysiotherapistReview(symptoms)
            ),
            streak: history.currentStreak + 1,
            simulatedResultLabels: resultOrder.compactMap { experience, label in
                sessionProvenance[experience] == .demo ? label : nil
            },
            assistedResultLabels: resultOrder.compactMap { experience, label in
                guard let count = assistedProgressCounts?[experience], count > 0 else { return nil }
                return "\(label) (\(count) assisted)"
            }
        )
    }
}
