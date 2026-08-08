import XCTest
@testable import RehabPal

final class AssessmentReportTests: XCTestCase {
    func testAssessmentParametersRemainFixedAndStricterThanGameplay() {
        let prescription = Prescription.demo
        let assessment = AssessmentProtocol(prescription: prescription)
        let game = GameplayTolerance(prescription: prescription)

        XCTAssertEqual(assessment.wristAttemptsPerDirection, 2)
        XCTAssertEqual(assessment.squeezeRepetitions, 5)
        XCTAssertLessThan(assessment.wristTolerance, game.wristTolerance)
        XCTAssertFalse(assessment.isAdaptive)
        XCTAssertTrue(game.isAdaptive)
    }

    func testFollowUpFlagUsesClinicianThresholdAndReportedIncrease() {
        let evaluator = SymptomEvaluator(reviewThreshold: 6)
        XCTAssertFalse(evaluator.needsPhysiotherapistReview(.comfortable))
        XCTAssertTrue(evaluator.needsPhysiotherapistReview(SymptomResult(
            discomfort: 6,
            increasedSinceStart: false,
            stiffness: 2,
            difficulty: 2,
            catchingOrLocking: false
        )))
        XCTAssertTrue(evaluator.needsPhysiotherapistReview(SymptomResult(
            discomfort: 3,
            increasedSinceStart: true,
            stiffness: 4,
            difficulty: 3,
            catchingOrLocking: false
        )))
    }

    func testReportKeepsAssessmentGameplayAndReportedMetricsSeparate() {
        let report = AfterCareReport.make(
            history: .fixture,
            assessment: .fixture,
            gameplay: [.fixture(for: .balance), .fixture(for: .squeeze)],
            symptoms: .comfortable,
            reviewThreshold: 6
        )

        XCTAssertEqual(report.assessment.currentWristControl, 73)
        XCTAssertEqual(report.gameplay.completedExercises, 2)
        XCTAssertEqual(report.patientReported.discomfort, 2)
        XCTAssertFalse(report.patientReported.reviewWithPhysiotherapist)
    }

    func testLowConfidenceAssessmentIsLabeledUnavailableInsteadOfFabricated() {
        let lowConfidence = AssessmentResult(
            wristControlScore: 99,
            closureConsistencyScore: 99,
            trackingConfidence: 0.2
        )
        let report = AfterCareReport.make(
            history: .fixture,
            assessment: lowConfidence,
            gameplay: [.fixture(for: .balance), .fixture(for: .squeeze)],
            symptoms: .comfortable,
            reviewThreshold: 6
        )

        XCTAssertNil(report.assessment.currentWristControl)
        XCTAssertNil(report.assessment.currentClosureConsistency)
        XCTAssertEqual(report.assessment.trackingNote, "Low tracking confidence—comparison unavailable")
    }
}
