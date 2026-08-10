import XCTest
@testable import RehabPal

final class AssessmentReportTests: XCTestCase {
    // Mutation caught: relying only on Demo provenance describes assisted
    // steps in an otherwise-live session as fully hand tracked.
    @MainActor
    func testReportDisclosesAssistedProgressInLiveSession() {
        let report = AfterCareReport.make(
            history: .fixture,
            assessment: .fixture,
            gameplay: [.fixture(for: .squeeze)],
            symptoms: .comfortable,
            reviewThreshold: 6,
            sessionProvenance: [.exercise(.squeeze): .live],
            assistedProgressCounts: [.exercise(.squeeze): 2]
        )
        XCTAssertEqual(report.assistedResultLabels, ["Squeeze Buddy (2 assisted)"])
        XCTAssertTrue(report.assistedProgressNote?.contains("NOT FULLY HAND-TRACKED") == true)
    }
    // Break caught: a screen or processor can silently replace a clinician-set
    // exercise or diagnostic goal with a hard-coded demo value.
    func testEverySessionRequestDerivesItsGoalFromPrescription() {
        let prescription = Prescription(
            affectedHand: .left,
            balanceTargetCount: 7,
            squeezeRepetitions: 9,
            squeezeCloseThreshold: 0.75,
            squeezeReopenThreshold: 0.25,
            squeezeHoldSeconds: 0.6,
            wristDiagnostic: WristDiagnosticPrescription(
                attemptsPerDirection: 3,
                targetDegrees: 18,
                targetToleranceDegrees: 4,
                offAxisToleranceDegrees: 3,
                holdSeconds: 0.4,
                neutralReturnToleranceDegrees: 4
            ),
            fingerDiagnostic: FingerDiagnosticPrescription(
                attemptsPerDigit: 4,
                extensionStabilitySeconds: 0.25,
                extensionStabilityToleranceDegrees: 2,
                minimumTotalExcursionDegrees: 16,
                extensionReturnToleranceDegrees: 7,
                thumbOppositionReduction: 0.3,
                thumbOppositionReturnTolerance: 0.08
            ),
            symptomReviewThreshold: 6
        )

        XCTAssertEqual(prescription.sessionRequest(for: .exercise(.balance)).goal, 7)
        XCTAssertEqual(prescription.sessionRequest(for: .exercise(.squeeze)).goal, 9)
        XCTAssertEqual(prescription.sessionRequest(for: .wristAssessment).goal, 15)
        XCTAssertEqual(prescription.sessionRequest(for: .handAssessment).goal, 20)
        XCTAssertEqual(prescription.wristDiagnostic.targetToleranceDegrees, 4)
        XCTAssertEqual(prescription.fingerDiagnostic.extensionReturnToleranceDegrees, 7)
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

    @MainActor
    func testReportKeepsAssessmentGameplayAndReportedMetricsSeparate() {
        let report = AfterCareReport.make(
            history: .fixture,
            assessment: .fixture,
            gameplay: [.fixture(for: .balance), .fixture(for: .squeeze)],
            symptoms: .comfortable,
            reviewThreshold: 6,
            sessionProvenance: [:]
        )

        XCTAssertEqual(report.assessment.currentWristControl, 73)
        XCTAssertEqual(report.gameplay.completedExercises, 2)
        XCTAssertEqual(report.patientReported.discomfort, 2)
        XCTAssertFalse(report.patientReported.reviewWithPhysiotherapist)
    }

    @MainActor
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
            reviewThreshold: 6,
            sessionProvenance: [:]
        )

        XCTAssertNil(report.assessment.currentWristControl)
        XCTAssertNil(report.assessment.currentClosureConsistency)
        XCTAssertEqual(report.assessment.trackingNote, "Low tracking confidence—comparison unavailable")
    }

    // Break caught: averaging wrist and finger confidence can hide a confident
    // wrist because unrelated fingers are weak, or expose unavailable fingers
    // because the wrist is strong.
    @MainActor
    func testReportGatesWristAndEachFingerByTheirOwnConfidence() {
        let availableIndex = DigitROMSummary(
            digit: .index,
            totalExcursion: 84,
            maximumFlexion: 75,
            maximumExtension: 5,
            consistency: 88,
            trackingConfidence: 0.9,
            attemptCount: 2
        )
        let unavailableRing = DigitROMSummary(
            digit: .ring,
            totalExcursion: 120,
            maximumFlexion: 100,
            maximumExtension: 0,
            consistency: 99,
            trackingConfidence: 0.3,
            attemptCount: 2
        )
        let assessment = AssessmentResult(
            wrist: .init(controlScore: 91, trackingConfidence: 0.95),
            handROM: [.index: availableIndex, .ring: unavailableRing]
        )

        let report = AfterCareReport.make(
            history: .fixture,
            assessment: assessment,
            gameplay: [],
            symptoms: .comfortable,
            reviewThreshold: 6,
            sessionProvenance: [:]
        )

        XCTAssertEqual(report.assessment.currentWristControl, 91)
        XCTAssertEqual(report.assessment.currentClosureConsistency, 88)
        XCTAssertEqual(assessment.todayTrendValue(for: .wrist), 91)
        XCTAssertEqual(assessment.todayTrendValue(for: .finger(.index)), 84)
        XCTAssertNil(assessment.todayTrendValue(for: .finger(.ring)))
    }

    // Break caught: strong fingers can make a low-confidence wrist appear as
    // today's orange chart point even though the wrist result is unavailable.
    @MainActor
    func testReportOmitsUnavailableWristTodayPointWithoutHidingAvailableFinger() {
        let availableMiddle = DigitROMSummary(
            digit: .middle,
            totalExcursion: 78,
            maximumFlexion: 70,
            maximumExtension: 4,
            consistency: 82,
            trackingConfidence: 0.85,
            attemptCount: 2
        )
        let assessment = AssessmentResult(
            wrist: .init(controlScore: 99, trackingConfidence: 0.2),
            handROM: [.middle: availableMiddle]
        )

        let report = AfterCareReport.make(
            history: .fixture,
            assessment: assessment,
            gameplay: [],
            symptoms: .comfortable,
            reviewThreshold: 6,
            sessionProvenance: [:]
        )

        XCTAssertNil(report.assessment.currentWristControl)
        XCTAssertEqual(report.assessment.currentClosureConsistency, 82)
        XCTAssertNil(assessment.todayTrendValue(for: .wrist))
        XCTAssertEqual(assessment.todayTrendValue(for: .finger(.middle)), 78)
    }

    // Break caught: Demo Mode outcomes can reach the report as ordinary measured
    // results after their session wrappers are aggregated.
    @MainActor
    func testReportRetainsExplicitSimulatedProvenance() {
        let provenance: [RehabExperience: SessionProvenance] = [
            .exercise(.balance): .demo,
            .exercise(.squeeze): .live,
            .wristAssessment: .demo,
            .handAssessment: .live
        ]

        let report = AfterCareReport.make(
            history: .fixture,
            assessment: .fixture,
            gameplay: [.fixture(for: .balance), .fixture(for: .squeeze)],
            symptoms: .comfortable,
            reviewThreshold: 6,
            sessionProvenance: provenance
        )

        XCTAssertEqual(report.simulatedResultLabels, ["Balance Platform", "Wrist assessment"])
        XCTAssertEqual(
            report.simulationNote,
            "SIMULATED DEMO RESULTS — Balance Platform, Wrist assessment"
        )
    }

    // Break caught: a simulated Sheep Drop outcome can be counted in the
    // report while omitted from the explicit simulation disclosure.
    @MainActor
    func testReportLabelsSimulatedSheepDropProvenance() {
        let report = AfterCareReport.make(
            history: .fixture,
            assessment: .fixture,
            gameplay: [.fixture(for: .sheepDrop)],
            symptoms: .comfortable,
            reviewThreshold: 6,
            sessionProvenance: [.exercise(.sheepDrop): .demo]
        )

        XCTAssertEqual(report.simulatedResultLabels, ["Sheep Drop"])
        XCTAssertEqual(report.simulationNote, "SIMULATED DEMO RESULTS — Sheep Drop")
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

    func testFingerROMCaptureWithoutTrackedSampleIsUnavailable() {
        var capture = FingerROMCaptureAccumulator()

        XCTAssertNil(capture.finish(trackingConfidence: 0.95))
    }

    func testFingerROMCaptureProducesFiniteExcursionFromTrackedSamples() {
        var capture = FingerROMCaptureAccumulator()
        capture.record(SIMD3<Float>(10, 20, 30))
        capture.record(SIMD3<Float>(40, 50, 60))

        let attempt = capture.finish(trackingConfidence: 0.95)

        XCTAssertEqual(attempt?.mcpExcursion, 30)
        XCTAssertEqual(attempt?.pipExcursion, 30)
        XCTAssertEqual(attempt?.dipExcursion, 30)
        XCTAssertEqual(attempt?.maximumFlexion, 60)
        XCTAssertEqual(attempt?.maximumExtension, 10)
        XCTAssertTrue(attempt?.totalExcursion.isFinite == true)
    }

    func testFingerROMCaptureIgnoresNonfiniteSamples() {
        var capture = FingerROMCaptureAccumulator()
        capture.record(SIMD3<Float>(.infinity, 20, 30))

        XCTAssertNil(capture.finish(trackingConfidence: 0.95))
    }

    func testFingerROMCaptureResetsAfterFinish() {
        var capture = FingerROMCaptureAccumulator()
        capture.record(SIMD3<Float>(10, 20, 30))

        XCTAssertNotNil(capture.finish(trackingConfidence: 0.95))
        XCTAssertNil(capture.finish(trackingConfidence: 0.95))
    }
}
