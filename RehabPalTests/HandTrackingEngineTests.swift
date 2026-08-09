import XCTest
@testable import RehabPal

@MainActor
final class HandTrackingEngineTests: XCTestCase {
    // Break caught: the injectable startup path could invoke ARKit even after
    // the engine had already reported the provider combination unsupported.
    func testUnsupportedEngineRejectsStartWithoutRunningSession() async {
        var runCount = 0
        let engine = HandTrackingEngine(
            isSupported: false,
            runSession: { runCount += 1 },
            stopSession: {}
        )

        do {
            try await engine.start()
            XCTFail("Expected unsupported tracking to fail before session.run")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Hand tracking is unavailable in this environment."
            )
        }

        XCTAssertEqual(runCount, 0)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(
            engine.lastError,
            "Hand tracking is unavailable in this environment."
        )
    }

    // Break caught: a delayed start from generation A can set error/running
    // state or stop the session after generation B has already succeeded.
    func testSupersededEngineStartCannotMutateNewerGeneration() async {
        let boundary = DelayedEngineStartBoundary()
        var stopCount = 0
        let engine = HandTrackingEngine(
            isSupported: true,
            runSession: { try await boundary.wait() },
            stopSession: { stopCount += 1 }
        )

        let first = Task { try await engine.start() }
        await boundary.waitForStartCount(1)
        engine.stop()
        let second = Task { try await engine.start() }
        await boundary.waitForStartCount(2)

        boundary.succeed(1)
        _ = await second.result
        XCTAssertTrue(engine.isRunning)
        XCTAssertNil(engine.lastError)

        boundary.fail(0, with: EngineStartError.lateFailure)
        _ = await first.result
        XCTAssertTrue(engine.isRunning)
        XCTAssertNil(engine.lastError)
        XCTAssertEqual(stopCount, 1)
    }

    // Break caught: cancellation while ARKitSession.run is suspended can later
    // publish a running engine and leak the underlying session.
    func testCancelledEngineStartCleansUpWhenBoundaryReturns() async {
        let boundary = DelayedEngineStartBoundary()
        var stopCount = 0
        let engine = HandTrackingEngine(
            isSupported: true,
            runSession: { try await boundary.wait() },
            stopSession: { stopCount += 1 }
        )

        let start = Task { try await engine.start() }
        await boundary.waitForStartCount(1)
        start.cancel()
        boundary.succeed(0)
        _ = await start.result

        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(stopCount, 1)
        XCTAssertNil(engine.latestJointFrame)
    }
}

@MainActor
private final class DelayedEngineStartBoundary {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]

    func wait() async throws {
        let id = nextID
        nextID += 1
        try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func succeed(_ id: Int) {
        continuations.removeValue(forKey: id)?.resume()
    }

    func fail(_ id: Int, with error: Error) {
        continuations.removeValue(forKey: id)?.resume(throwing: error)
    }

    func waitForStartCount(_ expected: Int) async {
        while nextID < expected {
            await Task.yield()
        }
    }
}

private enum EngineStartError: LocalizedError {
    case lateFailure

    var errorDescription: String? { "Late generation failure" }
}
