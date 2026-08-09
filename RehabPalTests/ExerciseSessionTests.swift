import XCTest
import simd
@testable import RehabPal

@MainActor
final class ExerciseSessionTests: XCTestCase {
    // Break caught: hard-coding the prototype's old eight targets ignores the clinician prescription.
    func testBalanceUsesThePrescriptionTenTargetGoal() {
        let session = BalanceSession(prescription: .demo, seed: 42)

        XCTAssertEqual(Prescription.demo.balanceTargetCount, 10)
        XCTAssertEqual(session.goal, 10)
        XCTAssertEqual(session.schedule.targets.count, 10)
        XCTAssertEqual(session.progress, SessionProgress(completed: 0, goal: 10, partial: 0))
    }

    // Break caught: an unsafe or non-deterministic spawn can overlap the ball or place the hole outside the walls.
    func testBalanceTargetsAreDeterministicAndSafelySeparatedFromTheBallSpawn() {
        let schedule = BalanceTargetSchedule(seed: 42, targetCount: 10)

        XCTAssertEqual(schedule, BalanceTargetSchedule(seed: 42, targetCount: 10))
        XCTAssertTrue(schedule.targets.allSatisfy { target in
            abs(target.x) <= 0.09 &&
            abs(target.z) <= 0.09 &&
            simd_distance(target.position, SIMD2<Float>(0, -0.066)) >= 0.084
        })
    }

    // Break caught: calibration from the wrong hand or from fewer than four level knuckles can steer the prescribed exercise.
    func testBalanceCalibratesOnlyFromTheAffectedHandAndFourLevelKnuckles() {
        var session = BalanceSession(prescription: .demo, seed: 7)
        let incomplete = calibratedFrame(hand: .right, wrist: matrix_identity_float4x4, omit: .littleFingerKnuckle)

        XCTAssertEqual(session.process(frame: calibratedFrame(hand: .left), ballPosition: .zero, ballEscaped: false), .waitingForCalibration)
        XCTAssertEqual(session.process(frame: incomplete, ballPosition: .zero, ballEscaped: false), .waitingForCalibration)
        XCTAssertFalse(session.isCalibrated)

        let event = session.process(frame: calibratedFrame(hand: .right), ballPosition: .zero, ballEscaped: false)
        XCTAssertEqual(event, .active(WristTilt(pitch: 0, roll: 0)))
        XCTAssertTrue(session.isCalibrated)
    }

    // Break caught: proximity outside the hole or tracking loss could increment progress, while a valid drop might fail to queue a reset.
    func testBalanceScoresOnlyTrackedBallDropsAndQueuesTheNextBallReset() {
        var session = BalanceSession(prescription: .demo, seed: 9)
        let frame = calibratedFrame(hand: .right)
        _ = session.process(frame: frame, ballPosition: .zero, ballEscaped: false)

        XCTAssertEqual(session.process(frame: nil, ballPosition: session.currentTarget.position, ballEscaped: false), .paused)
        XCTAssertEqual(session.completedSuccesses, 0)
        XCTAssertEqual(session.process(frame: frame, ballPosition: SIMD2<Float>(0.08, -0.066), ballEscaped: false), .resetBall(WristTilt(pitch: 0, roll: 0)))
        XCTAssertEqual(session.completedSuccesses, 0)
        XCTAssertEqual(
            session.process(frame: frame, ballPosition: BalanceTargetSchedule.ballStart, ballEscaped: false),
            .active(WristTilt(pitch: 0, roll: 0))
        )
        XCTAssertEqual(session.completedSuccesses, 0)

        let target = session.currentTarget.position
        XCTAssertEqual(
            session.process(frame: frame, ballPosition: target, ballEscaped: false),
            .scored(completed: 1, goal: 10, tilt: WristTilt(pitch: 0, roll: 0), isComplete: false)
        )
        XCTAssertEqual(session.completedSuccesses, 1)
    }

    // Break caught: an escaped physics body can silently score or remain lost instead of returning to a safe spawn.
    func testBalanceEscapeRequestsResetWithoutChangingScore() {
        var session = BalanceSession(prescription: .demo, seed: 11)
        let frame = calibratedFrame(hand: .right)
        _ = session.process(frame: frame, ballPosition: .zero, ballEscaped: false)

        XCTAssertEqual(
            session.process(frame: frame, ballPosition: SIMD2<Float>(1, 1), ballEscaped: true),
            .resetBall(WristTilt(pitch: 0, roll: 0))
        )
        XCTAssertEqual(session.completedSuccesses, 0)
    }

    // Break caught: resuming physics with partial ball motion or an obsolete neutral after a long interruption violates pause safety.
    func testBalancePauseFreezesPhysicsDiscardsThePartialBallAndCanRequireRecalibration() {
        var session = BalanceSession(prescription: .demo, seed: 13)
        let frame = calibratedFrame(hand: .right)
        _ = session.process(frame: frame, ballPosition: .zero, ballEscaped: false)

        session.pause(requiresRecalibration: false)
        XCTAssertEqual(session.process(frame: nil, ballPosition: .zero, ballEscaped: false), .paused)
        XCTAssertEqual(session.process(frame: frame, ballPosition: .zero, ballEscaped: false), .resetBall(WristTilt(pitch: 0, roll: 0)))
        XCTAssertTrue(session.isCalibrated)

        session.pause(requiresRecalibration: true)
        XCTAssertFalse(session.isCalibrated)
        XCTAssertEqual(session.process(frame: nil, ballPosition: .zero, ballEscaped: false), .paused)
        XCTAssertEqual(session.process(frame: frame, ballPosition: .zero, ballEscaped: false), .resetBall(WristTilt(pitch: 0, roll: 0)))
        XCTAssertTrue(session.isCalibrated)
    }

    // Break caught: absolute wrist rotation, yaw leakage, or a shared magnitude clamp can create unsafe tray motion.
    func testBalanceTiltIsNeutralRelativeYawFreeAndIndependentlyClamped() {
        let neutral = MovementMath.wristTransform(pitch: 0.18, roll: -0.12, yaw: 0.3)
        var session = BalanceSession(prescription: .demo, seed: 15)
        _ = session.process(
            frame: calibratedFrame(hand: .right, wrist: neutral),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        )

        let yawOnly = simd_mul(MovementMath.wristTransform(pitch: 0, roll: 0, yaw: 0.7), neutral)
        guard case let .active(yawTilt) = session.process(
            frame: calibratedFrame(hand: .right, wrist: yawOnly),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        ) else {
            return XCTFail("Expected active yaw-free tilt")
        }
        XCTAssertEqual(yawTilt.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(yawTilt.roll, 0, accuracy: 0.0001)

        let excessive = MovementMath.wristTransform(pitch: 0.8, roll: -0.7, yaw: 0.4)
        guard case let .active(tilt) = session.process(
            frame: calibratedFrame(hand: .right, wrist: excessive),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        ) else {
            return XCTFail("Expected active calibrated tilt")
        }
        XCTAssertEqual(tilt.pitch, .pi / 9, accuracy: 0.0001)
        XCTAssertEqual(tilt.roll, -.pi / 9, accuracy: 0.0001)
    }

    // Break caught: completing the target count with a fixture result loses the measured prescribed/completed dose.
    func testBalanceCompletionProducesAMeasuredGameplayResult() throws {
        var session = BalanceSession(prescription: .demo, seed: 17)
        let frame = calibratedFrame(hand: .right)
        _ = session.process(frame: frame, ballPosition: .zero, ballEscaped: false)

        for expected in 1...10 {
            let event = session.process(frame: frame, ballPosition: session.currentTarget.position, ballEscaped: false)
            guard case let .scored(completed, goal, _, isComplete) = event else {
                return XCTFail("Expected scored event")
            }
            XCTAssertEqual(completed, expected)
            XCTAssertEqual(goal, 10)
            XCTAssertEqual(isComplete, expected == 10)
        }

        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(result.exercise, .balance)
        XCTAssertEqual(result.prescribedDose, 10)
        XCTAssertEqual(result.completedDose, 10)
        XCTAssertTrue(result.trackingNote.contains("Measured"))
    }

    func testExerciseSessionsDoNotProgressWhileTrackingIsLost() {
        var squeeze = SqueezeSession(repetitions: 1, closeThreshold: 0.7, reopenThreshold: 0.3, holdSeconds: 0.5)
        XCTAssertFalse(squeeze.update(closure: 0.8, at: 0, isTracked: false))
        XCTAssertEqual(squeeze.completedRepetitions, 0)
    }

    func testSqueezeSessionCompletesOnlyAfterHeldHandReopens() {
        var session = SqueezeSession(repetitions: 1, closeThreshold: 0.7, reopenThreshold: 0.3, holdSeconds: 0.5)
        XCTAssertFalse(session.update(closure: 0.8, at: 0, isTracked: true))
        XCTAssertFalse(session.update(closure: 0.8, at: 0.6, isTracked: true))
        XCTAssertTrue(session.update(closure: 0.2, at: 0.7, isTracked: true))
        XCTAssertTrue(session.isComplete)
    }

    // Break caught: the non-prescribed hand can authorize the grasp and drive a prescribed repetition.
    func testSqueezeUsesOnlyTheAffectedHandAndShowsFaceAfterStableGraspGate() {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5
        )
        let metrics = squeezeMetrics()

        XCTAssertEqual(session.process(sample: .init(hand: .left, timestamp: 0, metrics: metrics)), .waitingForGrasp)
        XCTAssertEqual(session.process(sample: .init(hand: .left, timestamp: 1, metrics: metrics)), .waitingForGrasp)
        XCTAssertNil(session.facePose)

        XCTAssertEqual(session.process(sample: .init(hand: .right, timestamp: 2, metrics: metrics)), .stabilizingGrasp)
        for step in 1..<10 {
            XCTAssertEqual(
                session.process(sample: .init(
                    hand: .right,
                    timestamp: 2 + Double(step) * 0.1,
                    metrics: metrics
                )),
                .stabilizingGrasp
            )
        }
        guard case .active = session.process(sample: .init(hand: .right, timestamp: 3, metrics: metrics)) else {
            return XCTFail("Expected accepted grasp to activate squeeze")
        }
        XCTAssertNotNil(session.facePose)
        XCTAssertEqual(session.statusLabel, "Grasp pose detected (not object verified)")
    }

    // Break caught: repeatedly adding 0.1 can leave the final Demo Mode grasp sample just short
    // of the required one-second stability duration, forcing an extra button press.
    func testSqueezeDemoGraspSamplingCrossesOneSecondInOneAction() throws {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5,
            isSimulated: true
        )
        let timestamps = SqueezeDemoSampling.graspTimestamps(startingAt: 4)

        XCTAssertEqual(timestamps.count, 11)
        XCTAssertEqual(try XCTUnwrap(timestamps.last) - XCTUnwrap(timestamps.first), 1, accuracy: 0.000_000_1)
        for timestamp in timestamps.dropLast() {
            XCTAssertEqual(
                session.process(sample: squeezeSample(at: timestamp, closure: 0)),
                .stabilizingGrasp
            )
        }
        guard case .active = session.process(
            sample: squeezeSample(at: try XCTUnwrap(timestamps.last), closure: 0)
        ) else {
            return XCTFail("Expected one demo action to accept the grasp baseline")
        }
        let facePose = try XCTUnwrap(session.facePose)
        let presentation = SqueezeHUDPresentation(
            statusLabel: session.statusLabel,
            graspDetected: true
        )

        XCTAssertNil(facePose.surfacePosition(toward: nil))
        XCTAssertEqual(
            presentation.graspDisclosure,
            "Grasp pose detected (not object verified)"
        )
        XCTAssertEqual(
            presentation.demoActionTitle,
            "Complete close–hold–reopen (Demo Mode)"
        )
        XCTAssertEqual(
            session.process(sample: squeezeSample(at: 5.1, closure: 1)),
            .active(closure: 1, phase: .closing)
        )
    }

    // Break caught: threshold crossing can skip hold/reopen phases, double-count, or continue past the exact goal.
    func testSqueezeCountsCloseHoldReopenPhasesAndStopsAtExactGoal() throws {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5
        )
        acceptSqueezeBaseline(in: &session, startingAt: 0)

        XCTAssertEqual(session.process(sample: squeezeSample(at: 1.1, closure: 1)), .active(closure: 1, phase: .closing))
        XCTAssertEqual(session.process(sample: squeezeSample(at: 1.7, closure: 1)), .active(closure: 1, phase: .held))
        XCTAssertEqual(session.process(sample: squeezeSample(at: 1.8, closure: 0.5)), .active(closure: 0.5, phase: .reopening))
        XCTAssertEqual(
            session.process(sample: squeezeSample(at: 1.9, closure: 0)),
            .repCompleted(completed: 1, goal: 1, isComplete: true)
        )
        XCTAssertEqual(session.progress, SessionProgress(completed: 1, goal: 1, partial: 0))
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.process(sample: squeezeSample(at: 2, closure: 1)), .complete)
        XCTAssertEqual(session.completedRepetitions, 1)

        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(result.exercise, .squeeze)
        XCTAssertEqual(result.prescribedDose, 1)
        XCTAssertEqual(result.completedDose, 1)
        XCTAssertTrue(result.trackingNote.contains("Measured"))
        XCTAssertTrue(result.trackingNote.contains("not object verified"))
    }

    // Break caught: losing required joints can leave the face floating or resume a half-finished repetition.
    func testSqueezeInterruptionHidesFaceDiscardsPartialRepAndPreservesCompletedReps() {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 2,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5
        )
        acceptSqueezeBaseline(in: &session, startingAt: 0)
        _ = session.process(sample: squeezeSample(at: 1.1, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.7, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.8, closure: 0.5))
        _ = session.process(sample: squeezeSample(at: 1.9, closure: 0))
        XCTAssertEqual(session.completedRepetitions, 1)

        _ = session.process(sample: squeezeSample(at: 2, closure: 1))
        XCTAssertEqual(session.process(frame: nil), .paused)
        XCTAssertNil(session.facePose)
        XCTAssertEqual(session.phase, .open)
        XCTAssertEqual(session.completedRepetitions, 1)

        XCTAssertEqual(session.process(sample: squeezeSample(at: 2.2, closure: 0)), .active(closure: 0, phase: .open))
        session.pause(requiresRecalibration: true)
        XCTAssertEqual(session.process(sample: squeezeSample(at: 4.3, closure: 0)), .stabilizingGrasp)
        XCTAssertNil(session.facePose)
        XCTAssertEqual(session.completedRepetitions, 1)
    }

    // Break caught: synthetic button-driven repetitions can claim to be measured joint-tracking outcomes.
    func testSqueezeDemoCompletionLabelsThePayloadSimulated() throws {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5,
            isSimulated: true
        )
        acceptSqueezeBaseline(in: &session, startingAt: 0)
        _ = session.process(sample: squeezeSample(at: 1.1, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.7, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.8, closure: 0.5))
        _ = session.process(sample: squeezeSample(at: 1.9, closure: 0))

        let result = try XCTUnwrap(session.result)
        XCTAssertTrue(result.trackingNote.contains("Simulated"))
        XCTAssertFalse(result.trackingNote.contains("Measured"))
    }

    private func acceptSqueezeBaseline(in session: inout SqueezeSession, startingAt timestamp: TimeInterval) {
        for step in 0..<10 {
            XCTAssertEqual(
                session.process(sample: squeezeSample(
                    at: timestamp + Double(step) * 0.1,
                    closure: 0
                )),
                .stabilizingGrasp
            )
        }
        guard case .active = session.process(sample: squeezeSample(at: timestamp + 1, closure: 0)) else {
            return XCTFail("Expected stable grasp baseline")
        }
    }

    private func squeezeSample(at timestamp: TimeInterval, closure: Float) -> SqueezeHandSample {
        .init(
            hand: .right,
            timestamp: timestamp,
            metrics: squeezeMetrics(closure: closure)
        )
    }

    private func squeezeMetrics(closure: Float = 0) -> SqueezeHandMetrics {
        SqueezeHandMetrics(
            ballCenter: SIMD3<Float>(0, 0.05, -0.45),
            radius: 0.04,
            meanTipToPalmDistance: 0.08 * (1 - 0.5 * closure),
            meanFingerFlexion: 0.3 + (.pi / 2) * closure
        )
    }

    private func calibratedFrame(
        hand: AffectedHand,
        wrist: simd_float4x4 = matrix_identity_float4x4,
        omit omittedJoint: HandJoint? = nil
    ) -> HandJointFrame {
        let knuckles: [(HandJoint, Float)] = [
            (.indexFingerKnuckle, -0.03),
            (.middleFingerKnuckle, -0.01),
            (.ringFingerKnuckle, 0.01),
            (.littleFingerKnuckle, 0.03)
        ]
        var joints: [HandJoint: HandJointSample] = [.wrist: .tracked(transform: wrist)]
        for (joint, x) in knuckles where joint != omittedJoint {
            joints[joint] = .tracked(transform: simd_float4x4(translation: SIMD3<Float>(x, 0, 0)))
        }
        if omittedJoint == .wrist { joints[.wrist] = nil }
        return .synthetic(hand: hand, timestamp: 1, joints: joints)
    }
}
