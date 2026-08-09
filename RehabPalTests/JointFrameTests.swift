import XCTest
import simd
@testable import RehabPal

final class JointFrameTests: XCTestCase {
    // Break caught: exposing ARKit joint names outside the mapper would make frame consumers platform-coupled.
    func testSyntheticFrameUsesAppOwnedJointIdentifiers() {
        let frame = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 12,
            joints: [
                .wrist: .tracked(transform: matrix_identity_float4x4),
                .indexFingerTip: .tracked(transform: simd_float4x4(translation: SIMD3<Float>(0.01, 0, 0)))
            ]
        )

        XCTAssertEqual(frame.hand, AffectedHand.right)
        XCTAssertEqual(frame.joint(.indexFingerTip)?.position, SIMD3<Float>(0.01, 0, 0))
        XCTAssertNil(frame.joint(.middleFingerTip))
    }

    // Break caught: accepting the non-prescribed chirality would score motion from the wrong hand.
    func testFrameFiltersForAffectedHand() {
        let leftFrame = HandJointFrame.synthetic(hand: .left, timestamp: 1, joints: [:])

        XCTAssertTrue(leftFrame.isForAffectedHand(.left))
        XCTAssertFalse(leftFrame.isForAffectedHand(.right))
    }

    // Break caught: reporting good confidence when a required joint is absent or untracked would let processors act on incomplete data.
    func testFrameConfidenceRequiresEveryRequestedTrackedJoint() {
        let frame = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 1,
            joints: [
                .wrist: .tracked(transform: matrix_identity_float4x4),
                .indexFingerTip: .untracked
            ]
        )

        XCTAssertEqual(frame.confidence(requiring: Set([HandJoint.wrist])), TrackingQuality.good)
        XCTAssertEqual(frame.confidence(requiring: Set([.wrist, .indexFingerTip])), TrackingQuality.low)
        XCTAssertEqual(frame.confidence(requiring: Set([.thumbTip])), TrackingQuality.unavailable)
    }

    // Break caught: calibration without every level knuckle would establish a neutral reference from incomplete tracking.
    func testCalibrationRequiresWristAndFourLevelKnuckles() {
        let incomplete = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 1,
            joints: [
                .wrist: .tracked(transform: matrix_identity_float4x4),
                .indexFingerKnuckle: .tracked(transform: matrix_identity_float4x4),
                .middleFingerKnuckle: .tracked(transform: matrix_identity_float4x4),
                .ringFingerKnuckle: .tracked(transform: matrix_identity_float4x4)
            ]
        )
        let complete = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 2,
            joints: Dictionary(uniqueKeysWithValues: WristNeutralCalibration.requiredJoints.map { joint in
                (joint, .tracked(transform: matrix_identity_float4x4))
            })
        )

        XCTAssertNil(WristNeutralCalibration.capture(from: incomplete))
        XCTAssertNotNil(WristNeutralCalibration.capture(from: complete))
    }

    // Break caught: accepting knuckles at materially different heights makes an unstable, non-level pose neutral.
    func testCalibrationRejectsKnucklesThatAreNotLevel() {
        var joints = Dictionary(uniqueKeysWithValues: WristNeutralCalibration.requiredJoints.map { joint in
            (joint, HandJointSample.tracked(transform: matrix_identity_float4x4))
        })
        joints[.littleFingerKnuckle] = .tracked(transform: simd_float4x4(
            translation: SIMD3<Float>(0, 0.02, 0)
        ))
        let frame = HandJointFrame.synthetic(hand: .right, timestamp: 1, joints: joints)

        XCTAssertNil(WristNeutralCalibration.capture(from: frame))
    }

    // Break caught: a tracked knuckle with a non-finite transform can otherwise pass confidence and height checks as a neutral pose.
    func testCalibrationRejectsNonFiniteRequiredKnuckleTransform() {
        var joints = Dictionary(uniqueKeysWithValues: WristNeutralCalibration.requiredJoints.map { joint in
            (joint, HandJointSample.tracked(transform: matrix_identity_float4x4))
        })
        joints[.indexFingerKnuckle] = .tracked(transform: simd_float4x4(
            translation: SIMD3<Float>(.nan, 0, 0)
        ))
        let frame = HandJointFrame.synthetic(hand: .right, timestamp: 1, joints: joints)

        XCTAssertNil(WristNeutralCalibration.capture(from: frame))
    }

    // Break caught: calculating absolute orientation instead of orientation relative to neutral moves the tray at rest.
    func testCalibrationMeasuresWristTiltRelativeToNeutral() throws {
        let neutral = wristTransform(pitch: 0.2, roll: -0.1, yaw: 0.5)
        let movement = wristTransform(pitch: 0.35, roll: -0.25, yaw: 0.9)
        let calibration = try XCTUnwrap(WristNeutralCalibration(wristTransform: neutral))

        let tilt = calibration.tilt(for: movement)

        XCTAssertEqual(tilt.pitch, 0.149, accuracy: 0.005)
        XCTAssertEqual(tilt.roll, -0.149, accuracy: 0.005)
    }

    // Break caught: removing yaw only after calibration lets a world-y rotation steer a hand that was calibrated while tilted.
    func testCalibrationIgnoresWorldYawAfterNonLevelNeutralPose() throws {
        let neutral = wristTransform(pitch: 0.25, roll: -0.2, yaw: 0.4)
        let yawChange = wristTransform(pitch: 0, roll: 0, yaw: 0.6)
        let calibration = try XCTUnwrap(WristNeutralCalibration(wristTransform: neutral))

        let tilt = calibration.tilt(for: yawChange * neutral)

        XCTAssertEqual(tilt.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(tilt.roll, 0, accuracy: 0.0001)
    }

    // Break caught: allowing yaw to influence tilt makes a horizontal hand rotation steer the balance tray.
    func testWristTiltIgnoresYaw() {
        let yawOnly = wristTransform(pitch: 0, roll: 0, yaw: 0.8)

        let tilt = MovementMath.wristTilt(relativeTransform: yawOnly)

        XCTAssertEqual(tilt.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(tilt.roll, 0, accuracy: 0.0001)
    }

    // Break caught: sharing a total tilt cap between axes would suppress a valid second axis; skipping it can create unsafe tray angles.
    func testWristTiltClampsPitchAndRollIndependentlyToTwentyDegrees() {
        let excessiveTilt = wristTransform(pitch: 0.8, roll: -0.7, yaw: 0.4)

        let tilt = MovementMath.wristTilt(relativeTransform: excessiveTilt)

        XCTAssertEqual(tilt.pitch, .pi / 9, accuracy: 0.0001)
        XCTAssertEqual(tilt.roll, -.pi / 9, accuracy: 0.0001)
    }

    // Break caught: a fallback that publishes only legacy observations cannot drive joint-frame processors or preserve chirality.
    @MainActor
    func testSyntheticSourcePublishesTrackedFrameForConfiguredHand() throws {
        let source = SyntheticMovementSource(hand: .left)
        source.setWrist(direction: .right, progress: 0.5, at: 3)

        XCTAssertEqual(source.latestJointFrame?.hand, AffectedHand.left)
        XCTAssertEqual(
            source.latestJointFrame?.confidence(requiring: Set<HandJoint>([.wrist, .indexFingerKnuckle])),
            TrackingQuality.good
        )
        let indexTip = try XCTUnwrap(source.latestJointFrame?.joint(.indexFingerTip)?.position)
        XCTAssertEqual(indexTip.y, 0.0079, accuracy: 0.0001)
    }

    private func wristTransform(pitch: Float, roll: Float, yaw: Float) -> simd_float4x4 {
        let pitchRotation = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(pitch), sin(pitch), 0),
            SIMD4<Float>(0, -sin(pitch), cos(pitch), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        let rollRotation = simd_float4x4(columns: (
            SIMD4<Float>(cos(roll), sin(roll), 0, 0),
            SIMD4<Float>(-sin(roll), cos(roll), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        let yawRotation = simd_float4x4(columns: (
            SIMD4<Float>(cos(yaw), 0, -sin(yaw), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sin(yaw), 0, cos(yaw), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        return yawRotation * pitchRotation * rollRotation
    }
}
