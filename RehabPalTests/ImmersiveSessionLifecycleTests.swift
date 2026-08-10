import XCTest
@testable import RehabPal

final class ImmersiveSessionLifecycleTests: XCTestCase {
    @MainActor
    func testClosingAnOpenSpaceClearsStateAndRequestsDismissal() {
        let lifecycle = ImmersiveSessionLifecycle()
        let attempt = lifecycle.beginOpening()
        XCTAssertNotNil(attempt)
        XCTAssertEqual(lifecycle.completeOpening(attempt!), .accepted)
        XCTAssertEqual(lifecycle.state, .open)

        XCTAssertTrue(lifecycle.close())
        XCTAssertEqual(lifecycle.state, .closed)
    }

    @MainActor
    func testClosingAnInFlightOpenInvalidatesItAndStaleSuccessRequiresDismissal() {
        let lifecycle = ImmersiveSessionLifecycle()
        let attempt = lifecycle.beginOpening()
        XCTAssertNotNil(attempt)
        XCTAssertEqual(lifecycle.state, .opening(attempt!))

        XCTAssertTrue(lifecycle.close())
        XCTAssertEqual(lifecycle.state, .closed)
        XCTAssertEqual(lifecycle.completeOpening(attempt!), .dismissStaleOpen)
        XCTAssertEqual(lifecycle.state, .closed)
    }

    @MainActor
    func testStaleOpeningCannotDismissOrCloseANewerOwner() {
        let lifecycle = ImmersiveSessionLifecycle()
        let staleAttempt = lifecycle.beginOpening()!
        XCTAssertTrue(lifecycle.close())
        let currentAttempt = lifecycle.beginOpening()!

        XCTAssertEqual(
            lifecycle.completeOpening(staleAttempt),
            .ignoreStaleOpen
        )
        XCTAssertFalse(lifecycle.close(staleAttempt))
        XCTAssertEqual(lifecycle.state, .opening(currentAttempt))
        XCTAssertEqual(lifecycle.completeOpening(currentAttempt), .accepted)
        XCTAssertEqual(lifecycle.state, .open)
    }
}
