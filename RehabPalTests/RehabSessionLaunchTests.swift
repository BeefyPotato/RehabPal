import XCTest
@testable import RehabPal

@MainActor
final class RehabSessionLaunchTests: XCTestCase {
    // Break caught: ARKitSession.run can be awaited before the mixed immersive
    // space has actually opened, which violates the live-tracking lifecycle.
    func testLiveTrackingStartsOnlyAfterAsyncImmersiveOpenCompletes() async {
        let boundary = DelayedImmersiveOpenBoundary()
        let live = LaunchLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let lifecycle = ImmersiveSessionLifecycle()
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        var events: [String] = []
        live.onStart = { events.append("tracking-start") }

        let launch = Task { @MainActor in
            await RehabSessionLaunchSequence.startLive(
                request: request,
                coordinator: coordinator,
                lifecycle: lifecycle,
                open: {
                    events.append("open-began")
                    let result = await boundary.wait()
                    events.append("open-ended")
                    return result
                },
                dismiss: { events.append("dismiss") }
            )
        }
        await boundary.waitUntilSuspended()

        XCTAssertEqual(events, ["open-began"])
        XCTAssertEqual(live.startCount, 0)

        boundary.resume(with: .opened)
        let launched = await launch.value
        XCTAssertTrue(launched)
        XCTAssertEqual(events, ["open-began", "open-ended", "tracking-start"])
        XCTAssertEqual(lifecycle.state, .open)
        XCTAssertEqual(coordinator.provenance, .live)
    }

    // Break caught: cancellation while openImmersiveSpace is suspended can
    // leave an opened space or a late tracking start behind.
    func testCancelledDelayedOpenDismissesWithoutStartingTracking() async {
        let boundary = DelayedImmersiveOpenBoundary()
        let live = LaunchLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let lifecycle = ImmersiveSessionLifecycle()
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        var dismissCount = 0

        let launch = Task { @MainActor in
            await RehabSessionLaunchSequence.startLive(
                request: request,
                coordinator: coordinator,
                lifecycle: lifecycle,
                open: { await boundary.wait() },
                dismiss: { dismissCount += 1 }
            )
        }
        await boundary.waitUntilSuspended()
        launch.cancel()
        boundary.resume(with: .opened)

        let launched = await launch.value
        XCTAssertFalse(launched)
        XCTAssertEqual(live.startCount, 0)
        XCTAssertEqual(live.stopCount, 1)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(lifecycle.state, .closed)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // Break caught: if the lifecycle owner is externally invalidated while an
    // open request is pending, a later non-open result can leave the reserved
    // live startup generation stuck in `.starting`.
    func testInvalidatedOpenResultStillCancelsItsPreparedLiveStart() async {
        let boundary = DelayedImmersiveOpenBoundary()
        let live = LaunchLiveJointSource()
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: live
        )
        let lifecycle = ImmersiveSessionLifecycle()
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )

        let launch = Task { @MainActor in
            await RehabSessionLaunchSequence.startLive(
                request: request,
                coordinator: coordinator,
                lifecycle: lifecycle,
                open: { await boundary.wait() },
                dismiss: {}
            )
        }
        await boundary.waitUntilSuspended()
        XCTAssertTrue(lifecycle.close())
        boundary.resume(with: .userCancelled)

        let launched = await launch.value
        XCTAssertFalse(launched)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(live.startCount, 0)
        XCTAssertEqual(live.stopCount, 1)
    }

    // Break caught: a final live-start failure after an opened space can leave
    // the immersive scene open while recovery UI is shown in the window.
    func testLiveStartFailureClosesOpenedSpaceAndRetainsRecoveryFailure() async {
        let live = LaunchLiveJointSource(startError: LaunchError.denied)
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let lifecycle = ImmersiveSessionLifecycle()
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        var dismissCount = 0

        let launched = await RehabSessionLaunchSequence.startLive(
            request: request,
            coordinator: coordinator,
            lifecycle: lifecycle,
            open: { .opened },
            dismiss: { dismissCount += 1 }
        )

        XCTAssertFalse(launched)
        XCTAssertEqual(live.stopCount, 1)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(lifecycle.state, .closed)
        guard case .failed = coordinator.phase else {
            return XCTFail("Expected the recoverable live failure to remain visible")
        }
    }

    // Break caught: opening the demo space while the coordinator still holds
    // the preceding live failure can construct processors as measured rather
    // than simulated before Demo Mode is activated.
    func testDemoModeIsActiveBeforeImmersiveContentOpens() async {
        let live = LaunchLiveJointSource(startError: LaunchError.denied)
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: live
        )
        let lifecycle = ImmersiveSessionLifecycle()
        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        var demoWasActiveDuringOpen = false

        let launched = await RehabSessionLaunchSequence.startDemo(
            coordinator: coordinator,
            lifecycle: lifecycle,
            open: {
                demoWasActiveDuringOpen = coordinator.isUsingDemoMode
                return .opened
            },
            dismiss: {}
        )

        XCTAssertTrue(launched)
        XCTAssertTrue(demoWasActiveDuringOpen)
        XCTAssertTrue(coordinator.isUsingDemoMode)
        XCTAssertEqual(coordinator.authorization?.provenance, .demo)
    }
}

@MainActor
private final class DelayedImmersiveOpenBoundary {
    private var continuation: CheckedContinuation<RehabImmersiveOpenResult, Never>?
    private(set) var isSuspended = false

    func wait() async -> RehabImmersiveOpenResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isSuspended = true
        }
    }

    func resume(with result: RehabImmersiveOpenResult) {
        isSuspended = false
        continuation?.resume(returning: result)
        continuation = nil
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }
}

@MainActor
private final class LaunchLiveJointSource: LiveHandJointSession {
    var isSupported = true
    var latestJointFrame: HandJointFrame?
    var viewerPosition: SIMD3<Float>?
    var onStart: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let startError: Error?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start() async throws {
        startCount += 1
        onStart?()
        if let startError { throw startError }
    }

    func stop() {
        stopCount += 1
    }
}

private enum LaunchError: LocalizedError {
    case denied

    var errorDescription: String? { "Tracking permission was denied" }
}
