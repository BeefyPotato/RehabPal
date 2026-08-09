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

    func testFingerROMRequiresTwoAttemptsAndReportsExcursion() {
        var session = HandROMAssessmentSession(attemptsPerDigit: 2)
        let first = FingerROMAttempt(mcpExcursion: 35, pipExcursion: 42, dipExcursion: 24, maximumFlexion: 91, maximumExtension: 8, trackingConfidence: 0.9)
        let second = FingerROMAttempt(mcpExcursion: 37, pipExcursion: 40, dipExcursion: 26, maximumFlexion: 94, maximumExtension: 7, trackingConfidence: 0.95)

        XCTAssertFalse(session.record(first, for: .index))
        XCTAssertTrue(session.record(second, for: .index))
        XCTAssertEqual(session.summary(for: .index)!.totalExcursion, 102, accuracy: 0.01)
        XCTAssertEqual(session.summary(for: .index)?.attemptCount, 2)
    }

    func testLowConfidenceFingerROMIsUnavailable() {
        let summary = DigitROMSummary(digit: .ring, totalExcursion: 80, maximumFlexion: 75, maximumExtension: 5, consistency: 90, trackingConfidence: 0.3, attemptCount: 2)
        XCTAssertFalse(summary.isAvailable)
    }
}
