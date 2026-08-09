import XCTest
import simd
@testable import RehabPal

final class TableSurfaceTests: XCTestCase {
    // Break caught: accepting either endpoint makes the specified strictly
    // table-height-only range inclusive.
    func testHeightEndpointsAreRejected() {
        for height: Float in [0.60, 0.95] {
            var selector = TableSurfaceSelector(scanStartedAt: 10)
            let surface = makeSurface(height: height, timestamp: 10)

            XCTAssertNil(selector.receive(.added(surface), at: 10))
            XCTAssertNil(selector.receive(
                .updated(surface.with(timestamp: 10.36)),
                at: 10.36
            ))
        }
    }

    // Break caught: accepting a plane smaller on either axis lets the table
    // scene footprint extend beyond its physical surface.
    func testInsufficientExtentIsRejectedOnEitherAxis() {
        for extent: SIMD2<Float> in [[0.99, 0.70], [1.00, 0.69]] {
            var selector = TableSurfaceSelector(scanStartedAt: 10)
            let surface = makeSurface(extent: extent, timestamp: 10)

            XCTAssertNil(selector.receive(.added(surface), at: 10))
            XCTAssertNil(selector.receive(
                .updated(surface.with(timestamp: 10.36)),
                at: 10.36
            ))
        }
    }

    // Break caught: a single suitable plane observation could be accepted
    // without remaining compatible for the complete 0.35-second window.
    func testCompatibleUpdatesSelectDetectedSurfaceAfterStabilityWindow() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let surface = makeSurface(timestamp: 10)

        XCTAssertNil(selector.receive(.added(surface), at: 10))
        XCTAssertNil(selector.receive(
            .updated(surface.with(timestamp: 10.34)),
            at: 10.34
        ))
        let placement = selector.receive(
            .updated(surface.with(timestamp: 10.35)),
            at: 10.35
        )

        XCTAssertEqual(placement?.source, .detected)
        XCTAssertEqual(placement?.transform.translation, [0, 0.73, -0.55])
    }

    // Break caught: height motion larger than 1.5 cm could count toward the
    // original stability interval instead of restarting it.
    func testHeightDriftAboveLimitRestartsStabilityWindow() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let initial = makeSurface(height: 0.73, timestamp: 10)
        let drifted = makeSurface(
            id: initial.id,
            height: 0.746,
            timestamp: 10.35
        )

        XCTAssertNil(selector.receive(.added(initial), at: 10))
        XCTAssertNil(selector.receive(.updated(drifted), at: 10.35))
        XCTAssertNil(selector.receive(
            .updated(drifted.with(timestamp: 10.69)),
            at: 10.69
        ))
        XCTAssertEqual(
            selector.receive(
                .updated(drifted.with(timestamp: 10.70)),
                at: 10.70
            )?.source,
            .detected
        )
    }

    // Break caught: a plane whose normal rotates more than 5 degrees could
    // count toward the original stability interval.
    func testNormalDriftAboveLimitRestartsStabilityWindow() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let initial = makeSurface(normalDegrees: 0, timestamp: 10)
        let drifted = makeSurface(
            id: initial.id,
            normalDegrees: 5.1,
            timestamp: 10.35
        )

        XCTAssertNil(selector.receive(.added(initial), at: 10))
        XCTAssertNil(selector.receive(.updated(drifted), at: 10.35))
        XCTAssertEqual(
            selector.receive(
                .updated(drifted.with(timestamp: 10.70)),
                at: 10.70
            )?.source,
            .detected
        )
    }

    // Break caught: a removed anchor could leave its pre-removal stability
    // history alive and be selected immediately if its UUID reappears.
    func testRemovedAnchorLosesAccumulatedStability() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let surface = makeSurface(timestamp: 10)

        XCTAssertNil(selector.receive(.added(surface), at: 10))
        XCTAssertNil(selector.receive(
            .removed(id: surface.id, timestamp: 10.20),
            at: 10.20
        ))
        XCTAssertNil(selector.receive(
            .updated(surface.with(timestamp: 10.35)),
            at: 10.35
        ))
        XCTAssertEqual(
            selector.receive(
                .updated(surface.with(timestamp: 10.70)),
                at: 10.70
            )?.source,
            .detected
        )
    }

    // Break caught: losing tracking after selection could leave an unlocked
    // detected placement published as though its anchor were still valid.
    func testUntrackedSelectedSurfaceClearsDetectedPlacement() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let surface = makeSurface(timestamp: 10)
        XCTAssertNil(selector.receive(.added(surface), at: 10))
        XCTAssertEqual(
            selector.receive(
                .updated(surface.with(timestamp: 10.35)),
                at: 10.35
            )?.source,
            .detected
        )
        let untracked = makeSurface(
            id: surface.id,
            timestamp: 10.40,
            isTracked: false
        )

        XCTAssertNil(selector.receive(.updated(untracked), at: 10.40))
    }

    // Break caught: a later candidate could replace the first surface that
    // actually satisfied the complete stability rule.
    func testFirstStableCandidateRemainsAutomaticallySelected() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let first = makeSurface(x: -0.20, timestamp: 10)
        let second = makeSurface(x: 0.20, timestamp: 10.10)

        XCTAssertNil(selector.receive(.added(first), at: 10))
        XCTAssertNil(selector.receive(.added(second), at: 10.10))
        XCTAssertEqual(
            selector.receive(
                .updated(second.with(timestamp: 10.45)),
                at: 10.45
            )?.transform.translation.x,
            0.20
        )
        XCTAssertEqual(
            selector.receive(
                .updated(first.with(timestamp: 10.50)),
                at: 10.50
            )?.transform.translation.x,
            0.20
        )
    }

    // Break caught: fallback can appear before the full three-second scan or
    // fail to publish at the deadline.
    func testFallbackPublishesEstimatedReferencePlacementAtThreeSeconds() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)

        XCTAssertNil(selector.placement(at: 12.999))
        let placement = selector.placement(at: 13)

        XCTAssertEqual(placement?.source, .estimated)
        XCTAssertEqual(placement?.transform.translation, [0, 0.73, -0.55])
    }

    // Break caught: selected-plane updates after the first pickup could move
    // the scene despite the placement having been locked.
    func testLockPreventsLaterSelectedSurfaceMovement() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let surface = makeSurface(timestamp: 10)
        XCTAssertNil(selector.receive(.added(surface), at: 10))
        XCTAssertEqual(
            selector.receive(
                .updated(surface.with(timestamp: 10.35)),
                at: 10.35
            )?.transform.translation.x,
            0
        )

        let moved = makeSurface(id: surface.id, x: 0.05, timestamp: 10.40)
        XCTAssertEqual(
            selector.receive(.updated(moved), at: 10.40)?.transform.translation.x,
            0.05
        )
        selector.lock()
        let movedAgain = makeSurface(id: surface.id, x: 0.10, timestamp: 10.45)

        XCTAssertEqual(
            selector.receive(.updated(movedAgain), at: 10.45)?.transform.translation.x,
            0.05
        )
    }

    // Break caught: once selected, one excessive same-anchor pose jump can
    // strand the selector forever at the obsolete transform.
    func testSelectedSurfaceJumpInvalidatesAndRestabilizesAtNewPose() {
        var selector = TableSurfaceSelector(scanStartedAt: 10)
        let initial = makeSurface(height: 0.73, timestamp: 10)
        XCTAssertNil(selector.receive(.added(initial), at: 10))
        XCTAssertEqual(
            selector.receive(
                .updated(initial.with(timestamp: 10.35)),
                at: 10.35
            )?.transform.translation.y,
            0.73
        )

        let jumped = makeSurface(
            id: initial.id,
            height: 0.76,
            normalDegrees: 5.1,
            timestamp: 10.40
        )
        XCTAssertNil(selector.receive(.updated(jumped), at: 10.40))
        XCTAssertNil(selector.receive(
            .updated(jumped.with(timestamp: 10.74)),
            at: 10.74
        ))
        XCTAssertEqual(
            selector.receive(
                .updated(jumped.with(timestamp: 10.75)),
                at: 10.75
            )?.transform.translation.y,
            0.76
        )
    }

    private func makeSurface(
        id: UUID = UUID(),
        x: Float = 0,
        height: Float = 0.73,
        normalDegrees: Float = 0,
        extent: SIMD2<Float> = [1.0, 0.7],
        timestamp: TimeInterval,
        isTracked: Bool = true
    ) -> DetectedTableSurface {
        var transform = simd_float4x4(
            simd_quatf(
                angle: normalDegrees * .pi / 180,
                axis: [1, 0, 0]
            )
        )
        transform.columns.3 = SIMD4<Float>(x, height, -0.55, 1)
        return DetectedTableSurface(
            id: id,
            timestamp: timestamp,
            transform: transform,
            extent: extent,
            isTracked: isTracked
        )
    }
}

private extension DetectedTableSurface {
    func with(timestamp: TimeInterval) -> DetectedTableSurface {
        DetectedTableSurface(
            id: id,
            timestamp: timestamp,
            transform: transform,
            extent: extent,
            isTracked: isTracked
        )
    }
}
