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

    nonisolated static func make(
        history: DemoHistory,
        assessment: AssessmentResult,
        gameplay: [GameplayResult],
        symptoms: SymptomResult,
        reviewThreshold: Int
    ) -> AfterCareReport {
        let confident = assessment.trackingConfidence >= 0.6
        return AfterCareReport(
            assessment: AssessmentSection(
                baselineWristControl: history.baselineWristControl,
                previousWristControl: history.previousWristControl,
                currentWristControl: confident ? assessment.wristControlScore : nil,
                baselineClosureConsistency: history.baselineClosureConsistency,
                previousClosureConsistency: history.previousClosureConsistency,
                currentClosureConsistency: confident ? assessment.closureConsistencyScore : nil,
                trackingNote: confident
                    ? "Tracking confidence was sufficient for comparison"
                    : "Low tracking confidence—comparison unavailable"
            ),
            gameplay: GameplaySection(
                completedExercises: gameplay.filter { $0.completedDose >= $0.prescribedDose }.count,
                completedDose: gameplay.reduce(0) { $0 + $1.completedDose },
                prescribedDose: gameplay.reduce(0) { $0 + $1.prescribedDose }
            ),
            patientReported: PatientReportedSection(
                discomfort: symptoms.discomfort,
                stiffness: symptoms.stiffness,
                difficulty: symptoms.difficulty,
                increasedSinceStart: symptoms.increasedSinceStart,
                reviewWithPhysiotherapist: SymptomEvaluator(reviewThreshold: reviewThreshold)
                    .needsPhysiotherapistReview(symptoms)
            ),
            streak: history.currentStreak + 1
        )
    }
}
