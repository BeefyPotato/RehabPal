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
}
