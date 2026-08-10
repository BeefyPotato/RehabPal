import XCTest
import simd
@testable import RehabPal

final class JointFrameTests: XCTestCase {
    // Mutation caught: calibrating from the wrist joint instead of the hand
    // anchor makes an independently rotating wrist joint steer the tray.
    func testBalanceCalibrationUsesAnchorOrientationNotWristJointOrientation() throws {
        let anchor = MovementMath.wristTransform(pitch: 0.2, roll: -0.1, yaw: 0.3)
        let wrist = MovementMath.wristTransform(pitch: -0.6, roll: 0.5, yaw: -0.4)
        let frame = referenceCalibrationFrame(timestamp: 1, anchorTransform: anchor, wristTransform: wrist)
        let calibration = try XCTUnwrap(WristNeutralCalibration.capture(from: frame))
        let movedAnchor = MovementMath.wristTransform(pitch: 0.45, roll: 0.2, yaw: 0.8)
        let moved = referenceCalibrationFrame(timestamp: 2, anchorTransform: movedAnchor, wristTransform: wrist)

        let rotation = try XCTUnwrap(calibration.relativeRotation(for: moved))
        assertQuaternion(rotation, equals: simd_quatf(movedAnchor) * simd_quatf(anchor).inverse)
    }

    // Mutation caught: a height-only predicate accepts curved knuckles or a
    // line whose across-hand axis is too steep.
    func testReferenceCalibrationPredicateUsesExactHorizontalStraightBoundaries() {
        XCTAssertTrue(WristNeutralCalibration.isReferencePose(referenceCalibrationFrame(timestamp: 1)))
        XCTAssertFalse(WristNeutralCalibration.isReferencePose(referenceCalibrationFrame(
            timestamp: 2,
            middleOffset: [0, 0, 0.0121]
        )))
        XCTAssertFalse(WristNeutralCalibration.isReferencePose(referenceCalibrationFrame(
            timestamp: 3,
            littlePosition: [0.12, 0.0311, 0]
        )))
        XCTAssertTrue(WristNeutralCalibration.isReferencePose(referenceCalibrationFrame(
            timestamp: 4,
            middleOffset: [0, 0.006_666_667, 0],
            ringOffset: [0, 0.013_333_334, 0],
            littlePosition: [0.12, 0.02, 0]
        )))
        XCTAssertFalse(WristNeutralCalibration.isReferencePose(referenceCalibrationFrame(
            timestamp: 5,
            middleOffset: [0, 0.006_7, 0],
            ringOffset: [0, 0.013_4, 0],
            littlePosition: [0.12, 0.020_1, 0]
        )))
    }

    // Mutation caught: removing the reference span guard lets four coincident
    // knuckles calibrate because their Y spread is zero.
    func testReferenceCalibrationRejectsZeroSpan() {
        let sample = HandJointSample.tracked(transform: matrix_identity_float4x4)
        let frame = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 1,
            joints: [
                .wrist: sample,
                .indexFingerKnuckle: sample,
                .middleFingerKnuckle: sample,
                .ringFingerKnuckle: sample,
                .littleFingerKnuckle: sample
            ],
            anchorTransform: matrix_identity_float4x4
        )
        XCTAssertFalse(WristNeutralCalibration.isReferencePose(frame))
    }

    // Mutation caught: decomposing to pitch/roll, stripping yaw, or changing
    // either reference slerp factor produces a different tray quaternion.
    func testBalanceViewAppliesReferenceFullQuaternionSlerps() {
        let current = simd_quatf(angle: 0.2, axis: simd_normalize(SIMD3<Float>(1, 1, 0)))
        let delta = simd_quatf(angle: 0.7, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))
        let target = simd_slerp(simd_quatf(angle: 0, axis: [0, 1, 0]), delta, 0.6)
        let expected = simd_slerp(current, target, 0.08)
        assertQuaternion(BalanceReferenceRotation.smoothed(current: current, delta: delta), equals: expected)
    }
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

    // Break caught: a single latest-frame slot lets an interleaved update from
    // the unaffected hand overwrite the prescribed hand's usable frame.
    func testHandFrameDemultiplexerKeepsIndependentInterleavedHands() {
        var demultiplexer = HandJointFrameDemultiplexer()
        let left = HandJointFrame.synthetic(
            hand: .left,
            timestamp: 1,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )
        let right = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 2,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )

        demultiplexer.apply(.added(left))
        demultiplexer.apply(.updated(right))

        XCTAssertEqual(demultiplexer.frame(for: .left)?.timestamp, 1)
        XCTAssertEqual(demultiplexer.frame(for: .right)?.timestamp, 2)
    }

    // Break caught: an ARKit removal for the unaffected hand can erase the
    // affected frame, or a removal can retain a stale frame for that same hand.
    func testHandFrameDemultiplexerRemovalAffectsOnlyItsHand() {
        var demultiplexer = HandJointFrameDemultiplexer()
        let left = HandJointFrame.synthetic(
            hand: .left,
            timestamp: 10,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )
        let right = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 11,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )
        demultiplexer.apply(.added(left))
        demultiplexer.apply(.added(right))

        demultiplexer.apply(.removed(hand: .left, timestamp: 12))
        XCTAssertNil(demultiplexer.frame(for: .left))
        XCTAssertEqual(demultiplexer.frame(for: .right)?.timestamp, 11)

        demultiplexer.apply(.removed(hand: .right, timestamp: 13))
        XCTAssertNil(demultiplexer.frame(for: .right))
    }

    // Break caught: substituting render uptime for ARKit's update timestamp
    // defeats stale-frame detection and continuity checks downstream.
    func testHandFrameDemultiplexerPreservesUpdateTimestamp() {
        var demultiplexer = HandJointFrameDemultiplexer()
        let frame = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 42.125,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )

        demultiplexer.apply(.updated(frame))

        XCTAssertEqual(demultiplexer.frame(for: .right)?.timestamp, 42.125)
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

    // Mutation caught: deriving motion from the wrist joint instead of the
    // retained hand-anchor quaternion loses the reference implementation.
    func testCalibrationMeasuresFullAnchorRotationRelativeToNeutral() throws {
        let neutral = wristTransform(pitch: 0.2, roll: -0.1, yaw: 0.5)
        let movement = wristTransform(pitch: 0.35, roll: -0.25, yaw: 0.9)
        let calibration = try XCTUnwrap(WristNeutralCalibration(wristTransform: neutral))
        let frame = HandJointFrame.synthetic(hand: .right, timestamp: 1, joints: [
            .wrist: .tracked(transform: matrix_identity_float4x4)
        ], anchorTransform: movement)
        assertQuaternion(try XCTUnwrap(calibration.relativeRotation(for: frame)), equals: simd_quatf(movement) * simd_quatf(neutral).inverse)
    }

    // Mutation caught: stripping yaw differs from test8-2's full quaternion.
    func testCalibrationPreservesWorldYawAfterNonLevelNeutralPose() throws {
        let neutral = wristTransform(pitch: 0.25, roll: -0.2, yaw: 0.4)
        let yawChange = wristTransform(pitch: 0, roll: 0, yaw: 0.6)
        let calibration = try XCTUnwrap(WristNeutralCalibration(wristTransform: neutral))

        let movement = yawChange * neutral
        let frame = HandJointFrame.synthetic(hand: .right, timestamp: 1, joints: [
            .wrist: .tracked(transform: matrix_identity_float4x4)
        ], anchorTransform: movement)
        assertQuaternion(try XCTUnwrap(calibration.relativeRotation(for: frame)), equals: simd_quatf(movement) * simd_quatf(neutral).inverse)
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

    private func referenceCalibrationFrame(
        timestamp: TimeInterval,
        anchorTransform: simd_float4x4 = matrix_identity_float4x4,
        wristTransform: simd_float4x4 = matrix_identity_float4x4,
        middleOffset: SIMD3<Float> = .zero,
        ringOffset: SIMD3<Float> = .zero,
        littlePosition: SIMD3<Float> = [0.12, 0, 0]
    ) -> HandJointFrame {
        func tracked(_ position: SIMD3<Float>) -> HandJointSample {
            .tracked(transform: simd_float4x4(translation: position))
        }
        return .synthetic(
            hand: .right,
            timestamp: timestamp,
            joints: [
                .wrist: .tracked(transform: wristTransform),
                .indexFingerKnuckle: tracked([0, 0, 0]),
                .middleFingerKnuckle: tracked([0.04, 0, 0] + middleOffset),
                .ringFingerKnuckle: tracked([0.08, 0, 0] + ringOffset),
                .littleFingerKnuckle: tracked(littlePosition)
            ],
            anchorTransform: anchorTransform
        )
    }

    private func assertQuaternion(
        _ actual: simd_quatf,
        equals expected: simd_quatf,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dot = abs(simd_dot(actual.vector, expected.vector))
        XCTAssertEqual(dot, 1, accuracy: 0.0001, file: file, line: line)
    }
}
