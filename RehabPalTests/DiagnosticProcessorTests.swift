import XCTest
import simd
@testable import RehabPal

@MainActor
final class DiagnosticProcessorTests: XCTestCase {
    private let degree = Float.pi / 180

    // Break caught: a diagnostic could calibrate from the non-prescribed hand or skip the standardized target order.
    func testWristDiagnosticCalibratesAffectedHandAndUsesFiveTargetsTwice() {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 2)

        XCTAssertEqual(processor.process(frame: wristFrame(hand: .left, at: 0)), .waitingForCalibration)
        XCTAssertFalse(processor.isCalibrated)
        XCTAssertEqual(processor.process(frame: wristFrame(hand: .right, at: 0.1)), .ready(target: .center, attempt: 1, goal: 10))
        XCTAssertTrue(processor.isCalibrated)
        XCTAssertEqual(processor.targetSequence, [
            .center, .center,
            .forward, .forward,
            .backward, .backward,
            .left, .left,
            .right, .right
        ])
        XCTAssertEqual(processor.progress, SessionProgress(completed: 0, goal: 10, partial: 0))
    }

    // Break caught: a directional attempt could accept the wrong magnitude, excessive off-axis motion, or a discontinuous short hold.
    func testWristDiagnosticRequiresTwentyDegreesWithinFiveDegreesAndContinuousHalfSecondHold() {
        var processor = WristDiagnosticProcessor(
            affectedHand: .right,
            attemptsPerTarget: 1,
            maximumInterFrameGap: 0.1
        )
        _ = processor.process(frame: wristFrame(at: 0))
        completeWristAttempt(.center, processor: &processor, startingAt: 0.1)
        XCTAssertEqual(processor.currentTarget, .forward)

        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1, pitchDegrees: 14.9)),
            .ready(target: .forward, attempt: 2, goal: 5)
        )
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1.1, pitchDegrees: 20, rollDegrees: 5.1)),
            .ready(target: .forward, attempt: 2, goal: 5)
        )
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1.2, pitchDegrees: 15, rollDegrees: 5)),
            .holding(target: .forward, elapsed: 0, attempt: 2, goal: 5)
        )
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1.5, pitchDegrees: 26)),
            .ready(target: .forward, attempt: 2, goal: 5)
        )
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1.6, pitchDegrees: 20, rollDegrees: -5)),
            .holding(target: .forward, elapsed: 0, attempt: 2, goal: 5)
        )
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1.8, pitchDegrees: 20)),
            .holding(target: .forward, elapsed: 0, attempt: 2, goal: 5)
        )
        for timestamp in [1.9, 2.0, 2.1, 2.2] {
            _ = processor.process(frame: wristFrame(at: timestamp, pitchDegrees: 20))
        }
        guard case let .holding(target, elapsed, attempt, goal) = processor.process(
            frame: wristFrame(at: 2.29, pitchDegrees: 20)
        ) else {
            return XCTFail("Expected the continuous hold to remain just below 0.5 seconds")
        }
        XCTAssertEqual(target, .forward)
        XCTAssertEqual(elapsed, 0.49, accuracy: 0.000_001)
        XCTAssertEqual(attempt, 2)
        XCTAssertEqual(goal, 5)
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 2.3, pitchDegrees: 20)),
            .returnToNeutral(target: .forward, attempt: 2, goal: 5)
        )
        XCTAssertEqual(processor.progress.completed, 1)
    }

    // Break caught: reaching a target could count immediately without a neutral return inside the inclusive five-degree boundary.
    func testWristDiagnosticCompletesOnlyAfterNeutralReturnWithinFiveDegreesAndAdvancesAutomatically() {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 1)
        _ = processor.process(frame: wristFrame(at: 0))
        completeWristAttempt(.center, processor: &processor, startingAt: 0.1)
        for step in 0...5 {
            _ = processor.process(frame: wristFrame(
                at: 1 + Double(step) / 10,
                pitchDegrees: 20
            ))
        }

        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1.6, pitchDegrees: 5.1)),
            .returnToNeutral(target: .forward, attempt: 2, goal: 5)
        )
        XCTAssertEqual(processor.completedAttempts, 1)
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 1.7, pitchDegrees: 5, rollDegrees: -5)),
            .attemptCompleted(completed: 2, goal: 5, nextTarget: .backward)
        )
        XCTAssertEqual(processor.currentTarget, .backward)
        XCTAssertEqual(processor.progress, SessionProgress(completed: 2, goal: 5, partial: 0))
    }

    // Break caught: the standardized score could use radians, omit jitter, round out of range, or escape the zero-to-100 clamp.
    func testWristDiagnosticScoreUsesMeanDegreeErrorAndHoldJitterWithClamping() {
        XCTAssertEqual(
            WristDiagnosticProcessor.targetErrorDegrees(
                primaryDegrees: 20,
                targetDegrees: 20,
                offAxisDegrees: 3
            ),
            3,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WristDiagnosticProcessor.controlScore(
                targetErrorsDegrees: [2, 4],
                holdJitterDegrees: [1, 3]
            ),
            88
        )
        XCTAssertEqual(
            WristDiagnosticProcessor.controlScore(
                targetErrorsDegrees: [80],
                holdJitterDegrees: [30]
            ),
            0
        )
        XCTAssertEqual(
            WristDiagnosticProcessor.controlScore(
                targetErrorsDegrees: [],
                holdJitterDegrees: []
            ),
            100
        )
    }

    // Break caught: a completed wrist sequence could still return the old fixture instead of the processor's measured score and confidence.
    func testWristDiagnosticReturnsMeasuredResultAfterAllFiveAttempts() throws {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 1)
        _ = processor.process(frame: wristFrame(at: 0))
        var timestamp: TimeInterval = 0.1
        for target in WristAssessmentTarget.allCases {
            completeWristAttempt(target, processor: &processor, startingAt: timestamp)
            timestamp += 1
        }

        let result = try XCTUnwrap(processor.result)
        XCTAssertEqual(processor.completedAttempts, 5)
        XCTAssertEqual(result.controlScore, 100)
        XCTAssertEqual(result.trackingConfidence, 1, accuracy: 0.001)
    }

    // Break caught: tracking loss could retain a partial hold, count invalid required frames, or erase completed attempts.
    func testWristTrackingLossDiscardsPartialAttemptPreservesCompletedAndReportsFrameConfidence() {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 1)
        _ = processor.process(frame: wristFrame(at: 0))
        completeWristAttempt(.center, processor: &processor, startingAt: 0.1)
        _ = processor.process(frame: wristFrame(at: 1, pitchDegrees: 20))

        XCTAssertEqual(processor.process(frame: nil), .paused)
        XCTAssertEqual(processor.completedAttempts, 1)
        XCTAssertEqual(processor.progress, SessionProgress(completed: 1, goal: 5, partial: 0))
        XCTAssertLessThan(processor.trackingConfidence, 1)

        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 2, pitchDegrees: 20)),
            .holding(target: .forward, elapsed: 0, attempt: 2, goal: 5)
        )
        XCTAssertEqual(
            processor.process(frame: wristFrame(at: 2.4, pitchDegrees: 20)),
            .holding(target: .forward, elapsed: 0, attempt: 2, goal: 5)
        )
    }

    // Break caught: a present-but-nonfinite wrist transform could be counted as a valid required frame and contaminate the score.
    func testWristDiagnosticRejectsNonfiniteTrackedFrame() {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 1)
        _ = processor.process(frame: wristFrame(at: 0))
        var joints = wristFrame(at: 0.1).joints
        joints[.wrist] = .tracked(transform: simd_float4x4(
            translation: SIMD3<Float>(.nan, 0, 0)
        ))

        XCTAssertEqual(
            processor.process(frame: .synthetic(hand: .right, timestamp: 0.1, joints: joints)),
            .paused
        )
        XCTAssertEqual(processor.trackingConfidence, 0.5, accuracy: 0.001)
    }

    // Break caught: RealityKit render polling can read one ARKit frame repeatedly and falsely drive frame confidence toward zero.
    func testWristDiagnosticCountsEachTimestampOnlyOnceForConfidence() {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 1)
        _ = processor.process(frame: wristFrame(at: 0))
        let target = wristFrame(at: 0.1)

        for _ in 0..<100 {
            _ = processor.process(frame: target)
        }

        XCTAssertEqual(processor.trackingConfidence, 1, accuracy: 0.001)
    }

    // Break caught: recalibration could clear the confidence watermark and count one recovered ARKit frame twice.
    func testWristRecalibrationPreservesRecoveredFrameConfidenceWatermark() {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 1)
        _ = processor.process(frame: wristFrame(at: 0))
        _ = processor.process(frame: nil)
        let recoveredFrame = wristFrame(at: 1)
        _ = processor.process(frame: recoveredFrame)
        XCTAssertEqual(processor.trackingConfidence, 2.0 / 3.0, accuracy: 0.001)

        processor.pause(requiresRecalibration: true)
        for _ in 0..<100 {
            XCTAssertEqual(
                processor.process(frame: recoveredFrame),
                .waitingForCalibration
            )
        }

        XCTAssertEqual(processor.trackingConfidence, 2.0 / 3.0, accuracy: 0.001)
    }

    // Break caught: a missing observation can be read by many render updates and must count only once for confidence.
    func testWristDiagnosticConsumesMissingObservationGenerationOnce() {
        var processor = WristDiagnosticProcessor(affectedHand: .right, attemptsPerTarget: 1)
        let missing = HandJointFrameObservation(sequence: 1, timestamp: 0, frame: nil)

        _ = processor.process(observation: missing)
        _ = processor.process(observation: missing)
        _ = processor.process(observation: HandJointFrameObservation(
            sequence: 2,
            timestamp: 0.1,
            frame: wristFrame(at: 0.1)
        ))

        XCTAssertEqual(processor.trackingConfidence, 0.5, accuracy: 0.001)
    }

    // Break caught: using the interior joint angle directly reports extension as maximum flexion instead of converting 180° minus interior angle.
    func testFingerMetricsConvertInteriorAnglesToFlexion() {
        let metrics = FingerROMMetrics(
            interiorAngles: SIMD3<Float>(180, 150, 90),
            oppositionDistance: nil
        )

        XCTAssertEqual(metrics.flexionAngles, SIMD3<Float>(0, 30, 90))
        XCTAssertEqual(metrics.totalFlexion, 120)
    }

    // Break caught: an incomplete digit chain could be treated as a confident affected-hand sample.
    func testFingerMetricsCaptureRequiresTheCurrentDigitJointChain() throws {
        let complete = fingerFrame(digit: .index, at: 0, interiorDegrees: 90)
        let metrics = try XCTUnwrap(FingerROMMetrics.capture(from: complete, digit: .index))

        XCTAssertEqual(metrics.flexionAngles.x, 90, accuracy: 0.001)
        XCTAssertEqual(metrics.flexionAngles.y, 90, accuracy: 0.001)
        XCTAssertEqual(metrics.flexionAngles.z, 90, accuracy: 0.001)

        var incompleteJoints = complete.joints
        incompleteJoints[.indexFingerIntermediateTip] = nil
        let incomplete = HandJointFrame.synthetic(hand: .right, timestamp: 1, joints: incompleteJoints)
        XCTAssertNil(FingerROMMetrics.capture(from: incomplete, digit: .index))
    }

    // Break caught: finger capture could start from one transient extension frame or accept less than 15 degrees of total excursion.
    func testFingerDiagnosticRequiresStableExtensionForPointThreeSecondsAndFifteenDegreeExcursion() {
        var processor = FingerROMDiagnosticProcessor(
            affectedHand: .right,
            attemptsPerDigit: 2,
            maximumInterFrameGap: 0.1
        )
        let extended = fingerSample(.thumb, at: 0, flexion: [1, 1, 0], opposition: 0.08)

        XCTAssertEqual(processor.process(sample: extended), .stabilizingExtension(digit: .thumb, attempt: 1, goal: 10))
        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0.29, flexion: [1, 1, 0], opposition: 0.08)),
            .stabilizingExtension(digit: .thumb, attempt: 1, goal: 10)
        )
        for timestamp in [0.39, 0.49] {
            _ = processor.process(sample: fingerSample(.thumb, at: timestamp, flexion: [1, 1, 0], opposition: 0.08))
        }
        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0.59, flexion: [1, 1, 0], opposition: 0.08)),
            .capturingMotion(digit: .thumb, attempt: 1, goal: 10)
        )
        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0.69, flexion: [10, 4, 0], opposition: 0.07)),
            .capturingMotion(digit: .thumb, attempt: 1, goal: 10)
        )
        XCTAssertEqual(processor.completedAttempts, 0)
        XCTAssertEqual(processor.progress.partial, 0.8, accuracy: 0.001)
    }

    // Break caught: thumb frames without the little-finger opposition requirement could inflate confidence or start calibration.
    func testThumbDiagnosticRequiresOppositionMeasurementForAValidFrame() {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)

        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0, flexion: .zero, opposition: nil)),
            .paused
        )
        XCTAssertEqual(processor.trackingConfidence, 0, accuracy: 0.001)
    }

    // Break caught: repeated reads of one invalid finger frame could be counted as many separate required frames.
    func testFingerDiagnosticCountsDuplicateInvalidTimestampOnceForConfidence() {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)
        _ = processor.process(sample: fingerSample(.thumb, at: 0, flexion: .zero, opposition: 0.08))
        let wrongHand = fingerSample(.thumb, hand: .left, at: 0.1, flexion: .zero, opposition: 0.08)

        for _ in 0..<100 {
            _ = processor.process(sample: wrongHand)
        }

        XCTAssertEqual(processor.trackingConfidence, 0.5, accuracy: 0.001)
    }

    // Break caught: a missing finger observation can be read by many render updates and must count only once for confidence.
    func testFingerDiagnosticConsumesMissingObservationGenerationOnce() {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)
        let missing = HandJointFrameObservation(sequence: 1, timestamp: 0, frame: nil)

        _ = processor.process(observation: missing)
        _ = processor.process(observation: missing)
        _ = processor.process(observation: HandJointFrameObservation(
            sequence: 2,
            timestamp: 0.1,
            frame: fingerFrame(digit: .thumb, at: 0.1, interiorDegrees: 180)
        ))

        XCTAssertEqual(processor.trackingConfidence, 0.5, accuracy: 0.001)
    }

    // Break caught: cumulative session confidence can make a later perfectly tracked digit inherit an earlier digit's tracking loss.
    func testFingerAttemptConfidenceIsScopedToTheCurrentAttempt() throws {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)
        completeFingerAttempt(.thumb, processor: &processor, startingAt: 0)

        _ = processor.process(frame: nil)
        completeFingerAttempt(.index, processor: &processor, startingAt: 1)
        completeFingerAttempt(.middle, processor: &processor, startingAt: 2)

        let thumb = try XCTUnwrap(processor.attempts[.thumb]?.first)
        let index = try XCTUnwrap(processor.attempts[.index]?.first)
        let middle = try XCTUnwrap(processor.attempts[.middle]?.first)
        XCTAssertEqual(thumb.trackingConfidence, 1, accuracy: 0.001)
        XCTAssertLessThan(index.trackingConfidence, 1)
        XCTAssertEqual(middle.trackingConfidence, 1, accuracy: 0.001)
    }

    // Break caught: a non-thumb attempt could complete without both sufficient excursion and a return inside eight degrees of extension.
    func testFingerDiagnosticReturnsWithinEightDegreesAndAdvancesSequentialAttempts() {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)
        establishFingerExtension(.thumb, processor: &processor, startingAt: 0, opposition: 0.08)
        _ = processor.process(sample: fingerSample(.thumb, at: 0.4, flexion: [18, 4, 0], opposition: 0.05))
        _ = processor.process(sample: fingerSample(.thumb, at: 0.5, flexion: [1, 1, 0], opposition: 0.079))
        XCTAssertEqual(processor.currentDigit, .index)

        establishFingerExtension(.index, processor: &processor, startingAt: 1, opposition: nil)
        XCTAssertEqual(
            processor.process(sample: fingerSample(.index, at: 1.4, flexion: [10, 5, 1], opposition: nil)),
            .returningToExtension(digit: .index, attempt: 2, goal: 5)
        )
        XCTAssertEqual(
            processor.process(sample: fingerSample(.index, at: 1.5, flexion: [8.1, 1, 0], opposition: nil)),
            .returningToExtension(digit: .index, attempt: 2, goal: 5)
        )
        XCTAssertEqual(processor.completedAttempts, 1)
        XCTAssertEqual(
            processor.process(sample: fingerSample(.index, at: 1.6, flexion: [8, 1, 0], opposition: nil)),
            .attemptCompleted(completed: 2, goal: 5, nextDigit: .middle)
        )
        XCTAssertEqual(processor.currentDigit, .middle)
    }

    // Break caught: unsigned extrema can let a flexed baseline moving toward extension satisfy the required flexion excursion.
    func testFingerDiagnosticRequiresExcursionInTheFlexionDirection() {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)
        for step in 0...3 {
            _ = processor.process(sample: fingerSample(
                .thumb,
                at: Double(step) / 10,
                flexion: [20, 20, 0],
                opposition: 0.08
            ))
        }

        XCTAssertEqual(
            processor.process(sample: fingerSample(
                .thumb,
                at: 0.4,
                flexion: [10, 10, 0],
                opposition: 0.05
            )),
            .capturingMotion(digit: .thumb, attempt: 1, goal: 5)
        )
        XCTAssertEqual(processor.completedAttempts, 0)
    }

    // Break caught: thumb motion could count without 25% opposition reduction or without returning within 10% of baseline distance.
    func testThumbRequiresTwentyFivePercentOppositionReductionAndTenPercentReturn() {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)
        establishFingerExtension(.thumb, processor: &processor, startingAt: 0, opposition: 0.08)

        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0.4, flexion: [18, 4, 0], opposition: 0.0601)),
            .capturingMotion(digit: .thumb, attempt: 1, goal: 5)
        )
        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0.5, flexion: [18, 4, 0], opposition: 0.06)),
            .returningToExtension(digit: .thumb, attempt: 1, goal: 5)
        )
        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0.6, flexion: [1, 1, 0], opposition: 0.0719)),
            .returningToExtension(digit: .thumb, attempt: 1, goal: 5)
        )
        XCTAssertEqual(
            processor.process(sample: fingerSample(.thumb, at: 0.7, flexion: [1, 1, 0], opposition: 0.072)),
            .attemptCompleted(completed: 1, goal: 5, nextDigit: .index)
        )
    }

    // Break caught: the ROM outcome could omit recorded extrema/confidence or stop short of all five digits and ten prescribed attempts.
    func testFingerDiagnosticCapturesExtremaConfidenceAndCompletesTenAttempts() throws {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 2)
        var timestamp: TimeInterval = 0

        for digit in HandDigit.allCases {
            for _ in 0..<2 {
                establishFingerExtension(digit, processor: &processor, startingAt: timestamp, opposition: digit == .thumb ? 0.08 : nil)
                timestamp += 0.4
                _ = processor.process(sample: fingerSample(digit, at: timestamp, flexion: [20, 10, 5], opposition: digit == .thumb ? 0.05 : nil))
                timestamp += 0.1
                _ = processor.process(sample: fingerSample(digit, at: timestamp, flexion: [0, 0, 0], opposition: digit == .thumb ? 0.08 : nil))
                timestamp += 0.1
            }
        }

        XCTAssertEqual(processor.progress, SessionProgress(completed: 10, goal: 10, partial: 0))
        let result = try XCTUnwrap(processor.result)
        XCTAssertEqual(Set(result.keys), Set(HandDigit.allCases))
        let middle = try XCTUnwrap(result[.middle])
        XCTAssertEqual(middle.attemptCount, 2)
        XCTAssertEqual(middle.maximumFlexion, 20, accuracy: 0.001)
        XCTAssertEqual(middle.maximumExtension, 0, accuracy: 0.001)
        XCTAssertEqual(middle.totalExcursion, 35, accuracy: 0.001)
        XCTAssertEqual(middle.trackingConfidence, 1, accuracy: 0.001)
    }

    // Break caught: wrong-hand or missing tracking could complete a partial finger attempt or erase completed digit progress.
    func testFingerTrackingLossDiscardsPartialAttemptAndPreservesCompletedAttempts() {
        var processor = FingerROMDiagnosticProcessor(affectedHand: .right, attemptsPerDigit: 1)
        establishFingerExtension(.thumb, processor: &processor, startingAt: 0, opposition: 0.08)
        _ = processor.process(sample: fingerSample(.thumb, at: 0.4, flexion: [20, 10, 5], opposition: 0.05))
        _ = processor.process(sample: fingerSample(.thumb, at: 0.5, flexion: [0, 0, 0], opposition: 0.08))
        XCTAssertEqual(processor.completedAttempts, 1)

        establishFingerExtension(.index, processor: &processor, startingAt: 1, opposition: nil)
        _ = processor.process(sample: fingerSample(.index, at: 1.4, flexion: [20, 10, 5], opposition: nil))
        XCTAssertEqual(processor.process(frame: nil), .paused)
        XCTAssertEqual(processor.completedAttempts, 1)
        XCTAssertEqual(processor.currentDigit, .index)
        XCTAssertEqual(processor.progress, SessionProgress(completed: 1, goal: 5, partial: 0))

        XCTAssertEqual(
            processor.process(sample: fingerSample(.index, hand: .left, at: 2, flexion: [0, 0, 0], opposition: nil)),
            .paused
        )
        XCTAssertLessThan(processor.trackingConfidence, 1)
    }

    // Break caught: diagnostics could reuse the exercise counter or hide explicit simulated provenance in their shared HUD.
    func testDiagnosticHUDShowsAttemptGoalPhaseAndDemoProvenance() {
        let presentation = DiagnosticHUDPresentation(
            progress: SessionProgress(completed: 1, goal: 10, partial: 0.5),
            subject: "Forward",
            phase: "Hold steady",
            isDemo: true
        )

        XCTAssertEqual(presentation.attemptLabel, "Attempt 2 / Goal 10")
        XCTAssertEqual(presentation.subjectLabel, "Forward")
        XCTAssertEqual(presentation.phaseLabel, "Hold steady")
        XCTAssertEqual(presentation.provenanceLabel, "SIMULATED")
    }

    private func completeWristAttempt(
        _ target: WristAssessmentTarget,
        processor: inout WristDiagnosticProcessor,
        startingAt timestamp: TimeInterval
    ) {
        let angles = wristAngles(for: target)
        for step in 0...5 {
            _ = processor.process(frame: wristFrame(
                at: timestamp + Double(step) / 10,
                pitchDegrees: angles.pitch,
                rollDegrees: angles.roll
            ))
        }
        _ = processor.process(frame: wristFrame(at: timestamp + 0.6))
    }

    private func wristAngles(for target: WristAssessmentTarget) -> (pitch: Float, roll: Float) {
        switch target {
        case .center: (0, 0)
        case .forward: (20, 0)
        case .backward: (-20, 0)
        case .left: (0, -20)
        case .right: (0, 20)
        }
    }

    private func wristFrame(
        hand: AffectedHand = .right,
        at timestamp: TimeInterval,
        pitchDegrees: Float = 0,
        rollDegrees: Float = 0
    ) -> HandJointFrame {
        let transform = MovementMath.wristTransform(
            pitch: pitchDegrees * degree,
            roll: rollDegrees * degree
        )
        let joints = Dictionary(uniqueKeysWithValues: WristNeutralCalibration.requiredJoints.map {
            ($0, HandJointSample.tracked(transform: transform))
        })
        return .synthetic(hand: hand, timestamp: timestamp, joints: joints)
    }

    private func establishFingerExtension(
        _ digit: HandDigit,
        processor: inout FingerROMDiagnosticProcessor,
        startingAt timestamp: TimeInterval,
        opposition: Float?
    ) {
        for step in 0...3 {
            _ = processor.process(sample: fingerSample(
                digit,
                at: timestamp + Double(step) / 10,
                flexion: [0, 0, 0],
                opposition: opposition
            ))
        }
    }

    private func completeFingerAttempt(
        _ digit: HandDigit,
        processor: inout FingerROMDiagnosticProcessor,
        startingAt timestamp: TimeInterval
    ) {
        establishFingerExtension(
            digit,
            processor: &processor,
            startingAt: timestamp,
            opposition: digit == .thumb ? 0.08 : nil
        )
        _ = processor.process(sample: fingerSample(
            digit,
            at: timestamp + 0.4,
            flexion: [20, 10, 5],
            opposition: digit == .thumb ? 0.05 : nil
        ))
        _ = processor.process(sample: fingerSample(
            digit,
            at: timestamp + 0.5,
            flexion: .zero,
            opposition: digit == .thumb ? 0.08 : nil
        ))
    }

    private func fingerSample(
        _ digit: HandDigit,
        hand: AffectedHand = .right,
        at timestamp: TimeInterval,
        flexion: SIMD3<Float>,
        opposition: Float?
    ) -> FingerDiagnosticSample {
        FingerDiagnosticSample(
            hand: hand,
            timestamp: timestamp,
            digit: digit,
            metrics: FingerROMMetrics(
                interiorAngles: SIMD3<Float>(repeating: 180) - flexion,
                oppositionDistance: opposition
            )
        )
    }

    private func fingerFrame(
        digit: HandDigit,
        at timestamp: TimeInterval,
        interiorDegrees _: Float
    ) -> HandJointFrame {
        let chain = FingerROMMetrics.requiredJoints(for: digit)
        var joints: [HandJoint: HandJointSample] = [:]
        for (index, joint) in chain.enumerated() {
            let segment = index / 2
            let isBentPoint = index.isMultiple(of: 2)
            let baseX = Float(segment) * 2
            let position: SIMD3<Float>
            if isBentPoint {
                position = [baseX, 0, 0]
            } else {
                position = [baseX + 1, 0, 0]
            }
            joints[joint] = .tracked(transform: simd_float4x4(translation: position))
        }

        // A 90-degree zig-zag gives a literal, independently checked fixture for all three interior angles.
        if digit != .thumb {
            let points: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [2, 1, 0], [2, 2, 0]]
            for (joint, position) in zip(chain, points) {
                joints[joint] = .tracked(transform: simd_float4x4(translation: position))
            }
        }
        return .synthetic(hand: .right, timestamp: timestamp, joints: joints)
    }
}
