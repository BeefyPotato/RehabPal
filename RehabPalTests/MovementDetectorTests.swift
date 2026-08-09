import XCTest
import simd
@testable import RehabPal

final class MovementDetectorTests: XCTestCase {
    func testAngleUsesKnownPerpendicularVectors() {
        let angle = MovementMath.angle(
            between: SIMD3<Float>(1, 0, 0),
            and: SIMD3<Float>(0, 1, 0)
        )
        XCTAssertEqual(angle, .pi / 2, accuracy: 0.0001)
    }

    func testWorldTransformComposesAnchorAndJointTranslations() {
        let anchor = simd_float4x4(translation: SIMD3<Float>(1, 2, 3))
        let joint = simd_float4x4(translation: SIMD3<Float>(0.5, -0.5, 1))
        let world = MovementMath.worldTransform(anchor: anchor, joint: joint)
        XCTAssertEqual(world.translation.x, 1.5, accuracy: 0.0001)
        XCTAssertEqual(world.translation.y, 1.5, accuracy: 0.0001)
        XCTAssertEqual(world.translation.z, 4, accuracy: 0.0001)
    }

    func testWristTargetUsesToleranceAndDominantAxis() {
        let detector = WristTargetDetector(targetMagnitude: 0.4, tolerance: 0.08)
        XCTAssertEqual(detector.classify(pitch: 0.43, roll: 0.05), .forward)
        XCTAssertEqual(detector.classify(pitch: -0.41, roll: 0.02), .backward)
        XCTAssertEqual(detector.classify(pitch: 0.01, roll: -0.45), .left)
        XCTAssertEqual(detector.classify(pitch: 0.03, roll: 0.42), .right)
        XCTAssertNil(detector.classify(pitch: 0.25, roll: 0.02))
    }

    func testSqueezeRequiresCloseHoldAndReopenWithoutDoubleCounting() {
        var detector = SqueezeRepDetector(closeThreshold: 0.7, reopenThreshold: 0.3, holdSeconds: 1)

        XCTAssertFalse(detector.update(closure: 0.1, at: 0, isTracked: true))
        XCTAssertFalse(detector.update(closure: 0.8, at: 0.2, isTracked: true))
        XCTAssertFalse(detector.update(closure: 0.8, at: 1.3, isTracked: true))
        XCTAssertTrue(detector.update(closure: 0.2, at: 1.5, isTracked: true))
        XCTAssertFalse(detector.update(closure: 0.1, at: 1.6, isTracked: true))
        XCTAssertEqual(detector.completedRepetitions, 1)
    }

    func testTrackingLossPausesHoldTimer() {
        var detector = SqueezeRepDetector(closeThreshold: 0.7, reopenThreshold: 0.3, holdSeconds: 1)
        XCTAssertFalse(detector.update(closure: 0.8, at: 0, isTracked: true))
        XCTAssertFalse(detector.update(closure: 0.8, at: 0.4, isTracked: false))
        XCTAssertFalse(detector.update(closure: 0.8, at: 5.4, isTracked: true))
        XCTAssertFalse(detector.update(closure: 0.2, at: 5.5, isTracked: true))
        XCTAssertFalse(detector.update(closure: 0.8, at: 6.1, isTracked: true))
        XCTAssertFalse(detector.update(closure: 0.8, at: 7.2, isTracked: true))
        XCTAssertTrue(detector.update(closure: 0.2, at: 7.3, isTracked: true))
    }

    // Break caught: a single plausible hand frame can falsely authorize the face and repetition detector.
    func testSqueezeGraspGateRequiresOneStableSecondOfCuppedHandMetrics() throws {
        var gate = SqueezeGraspGate(stabilityDuration: 1)
        let metrics = squeezeMetrics(radius: 0.04)

        XCTAssertNil(gate.update(metrics, at: 0))
        XCTAssertNil(gate.update(metrics, at: 0.99))
        let baseline = try XCTUnwrap(gate.update(metrics, at: 1))

        XCTAssertEqual(baseline.ballCenter, SIMD3<Float>(0.1, 0.2, -0.4))
        XCTAssertEqual(baseline.radius, 0.04, accuracy: 0.0001)
    }

    // Break caught: implausibly small or large grasp envelopes can be mistaken for a real stress-ball pose.
    func testSqueezeGraspGateEnforcesInclusiveTwoPointFiveToSixPointFiveCentimeterRadius() {
        var lowerBound = SqueezeGraspGate(stabilityDuration: 1)
        XCTAssertNil(lowerBound.update(squeezeMetrics(radius: 0.025), at: 0))
        XCTAssertNotNil(lowerBound.update(squeezeMetrics(radius: 0.025), at: 1))

        var upperBound = SqueezeGraspGate(stabilityDuration: 1)
        XCTAssertNil(upperBound.update(squeezeMetrics(radius: 0.065), at: 0))
        XCTAssertNotNil(upperBound.update(squeezeMetrics(radius: 0.065), at: 1))

        var tooSmall = SqueezeGraspGate(stabilityDuration: 1)
        XCTAssertNil(tooSmall.update(squeezeMetrics(radius: 0.0249), at: 0))
        XCTAssertNil(tooSmall.update(squeezeMetrics(radius: 0.0249), at: 1))

        var tooLarge = SqueezeGraspGate(stabilityDuration: 1)
        XCTAssertNil(tooLarge.update(squeezeMetrics(radius: 0.0651), at: 0))
        XCTAssertNil(tooLarge.update(squeezeMetrics(radius: 0.0651), at: 1))
    }

    // Break caught: a changing grasp envelope can pass merely because its first and last radii happen to match.
    func testSqueezeGraspGateRejectsMoreThanEighteenPercentRadiusVariationAcrossWindow() {
        var stable = SqueezeGraspGate(stabilityDuration: 1)
        XCTAssertNil(stable.update(squeezeMetrics(radius: 0.04), at: 0))
        XCTAssertNil(stable.update(squeezeMetrics(radius: 0.047), at: 0.5))
        XCTAssertNotNil(stable.update(squeezeMetrics(radius: 0.04), at: 1))

        var unstable = SqueezeGraspGate(stabilityDuration: 1)
        XCTAssertNil(unstable.update(squeezeMetrics(radius: 0.04), at: 0))
        XCTAssertNil(unstable.update(squeezeMetrics(radius: 0.048), at: 0.5))
        XCTAssertNil(unstable.update(squeezeMetrics(radius: 0.04), at: 1))
    }

    // Break caught: a translating hand can pass a radius-only gate and place the inferred face at a stale midpoint.
    func testSqueezeGraspGateRejectsSpatialDriftAcrossTheStabilityWindow() {
        var gate = SqueezeGraspGate(stabilityDuration: 1)
        XCTAssertNil(gate.update(squeezeMetrics(radius: 0.04), at: 0))
        XCTAssertNil(gate.update(
            squeezeMetrics(radius: 0.04, ballCenter: SIMD3<Float>(0.12, 0.2, -0.4)),
            at: 1
        ))
    }

    // Break caught: facial features can float inside, behind, or away from the inferred physical-ball surface.
    func testSqueezeFacePositionIsOnTheInferredSurfaceTowardTheViewer() {
        let pose = SqueezeFacePose(ballCenter: SIMD3<Float>(1, 2, 3), radius: 0.04)
        let position = pose.surfacePosition(toward: SIMD3<Float>(1, 2, 5))

        XCTAssertEqual(position.x, 1, accuracy: 0.0001)
        XCTAssertEqual(position.y, 2, accuracy: 0.0001)
        XCTAssertEqual(position.z, 3.04, accuracy: 0.0001)
    }

    // Break caught: closure derived from only distance or only flexion misrepresents the prescribed combined motion.
    func testSqueezeClosureNormalizesDistanceAndFlexionAgainstAcceptedBaseline() {
        let baseline = SqueezeBaseline(metrics: squeezeMetrics(
            radius: 0.04,
            meanTipToPalmDistance: 0.08,
            meanFingerFlexion: 0.2
        ))
        let halfDistanceAndHalfFlexion = squeezeMetrics(
            radius: 0.035,
            meanTipToPalmDistance: 0.04,
            meanFingerFlexion: 0.2 + .pi / 4
        )

        XCTAssertEqual(baseline.normalizedClosure(for: baseline.metrics), 0, accuracy: 0.0001)
        XCTAssertEqual(baseline.normalizedClosure(for: halfDistanceAndHalfFlexion), 0.75, accuracy: 0.0001)
    }

    // Break caught: joint-frame inference can omit a required joint or estimate the wrong envelope before gating.
    func testSqueezeMetricsCaptureRequiresEveryJointAndEstimatesTheKnownEnvelope() throws {
        let complete = squeezeJointFrame(omitting: nil)
        let metrics = try XCTUnwrap(SqueezeHandMetrics.capture(from: complete))

        XCTAssertEqual(metrics.ballCenter.x, 0, accuracy: 0.0002)
        XCTAssertEqual(metrics.ballCenter.y, 0.05, accuracy: 0.0002)
        XCTAssertEqual(metrics.ballCenter.z, -0.4, accuracy: 0.0002)
        XCTAssertEqual(metrics.radius, 0.04, accuracy: 0.0002)
        XCTAssertGreaterThan(metrics.meanFingerFlexion, SqueezeGraspGate.minimumCuppedFlexion)

        XCTAssertNil(SqueezeHandMetrics.capture(from: squeezeJointFrame(
            omitting: .littleFingerIntermediateBase
        )))
    }

    private func squeezeJointFrame(omitting omittedJoint: HandJoint?) -> HandJointFrame {
        let tips: [HandJoint: SIMD3<Float>] = [
            .thumbTip: [0.04, 0.05, -0.4],
            .indexFingerTip: [0.01236, 0.08804, -0.4],
            .middleFingerTip: [-0.03236, 0.07351, -0.4],
            .ringFingerTip: [-0.03236, 0.02649, -0.4],
            .littleFingerTip: [0.01236, 0.01196, -0.4]
        ]
        var joints = Dictionary(uniqueKeysWithValues: SqueezeHandMetrics.palmJoints.map { joint in
            (joint, HandJointSample.tracked(transform: simd_float4x4(
                translation: SIMD3<Float>(0, 0, -0.4)
            )))
        })
        for (joint, position) in tips {
            joints[joint] = .tracked(transform: simd_float4x4(translation: position))
        }
        for (knuckle, intermediate, tipJoint) in SqueezeHandMetrics.flexionJoints {
            guard let tip = tips[tipJoint] else { continue }
            joints[knuckle] = .tracked(transform: simd_float4x4(
                translation: tip + SIMD3<Float>(-0.02, 0, 0)
            ))
            joints[intermediate] = .tracked(transform: simd_float4x4(
                translation: tip + SIMD3<Float>(-0.01, 0.005, 0)
            ))
        }
        if let omittedJoint {
            joints[omittedJoint] = nil
        }
        return .synthetic(hand: .right, timestamp: 1, joints: joints)
    }

    private func squeezeMetrics(
        radius: Float,
        ballCenter: SIMD3<Float> = SIMD3<Float>(0.1, 0.2, -0.4),
        meanTipToPalmDistance: Float = 0.08,
        meanFingerFlexion: Float = 0.35
    ) -> SqueezeHandMetrics {
        SqueezeHandMetrics(
            ballCenter: ballCenter,
            radius: radius,
            meanTipToPalmDistance: meanTipToPalmDistance,
            meanFingerFlexion: meanFingerFlexion
        )
    }
}
