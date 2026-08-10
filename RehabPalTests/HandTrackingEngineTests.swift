import XCTest
import simd
@testable import RehabPal

@MainActor
final class HandTrackingEngineTests: XCTestCase {
    // Mutation caught: reusing one production runtime across start-stop-start
    // collapses two generations and lets stale provider work publish again.
    func testStartStopStartOwnsDistinctRuntimeGenerationsAndCurrentUpdates() async throws {
        let tables = TableUpdateBoundary()
        var starts = 0
        var stops = 0
        let engine = HandTrackingEngine(
            isSupported: true,
            runSession: { starts += 1 },
            stopSession: { stops += 1 },
            tableSurfaceUpdates: { tables.makeStream() }
        )

        try await engine.start()
        engine.stop()
        try await engine.start()
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(stops, 1)

        let stale = tableSurface(id: UUID(), x: -0.3, timestamp: 10)
        tables.yield(.added(stale), to: 0)
        await Task.yield()
        XCTAssertNil(engine.tablePlacement)

        let current = tableSurface(id: UUID(), x: 0.3, timestamp: 20)
        tables.yield(.added(current), to: 1)
        tables.yield(.updated(current.with(timestamp: 20.4)), to: 1)
        await waitUntil { engine.tablePlacement != nil }
        XCTAssertEqual(engine.tablePlacement?.transform.translation.x, 0.3)
    }

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

    // Break caught: plane work could require a second session start or fail
    // to publish through the engine's one shared live-tracking lifecycle.
    func testSingleStartBoundaryOwnsTableUpdatesAndStopClearsPublication() async throws {
        let updates = TableUpdateBoundary()
        var runCount = 0
        let engine = HandTrackingEngine(
            isSupported: true,
            runSession: { runCount += 1 },
            stopSession: {},
            tableSurfaceUpdates: { updates.makeStream() }
        )

        try await engine.start()
        let surface = tableSurface(id: UUID(), x: 0.15, timestamp: 10)
        updates.yield(.added(surface), to: 0)
        updates.yield(.updated(surface.with(timestamp: 10.4)), to: 0)
        await waitUntil { engine.tablePlacement != nil }

        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(engine.tablePlacement?.source, .detected)
        XCTAssertEqual(engine.tablePlacement?.transform.translation.x, 0.15)

        engine.stop()

        XCTAssertNil(engine.tablePlacement)
    }

    // Break caught: a cancelled plane stream from generation A could move the
    // table selected by generation B after a stop/restart race.
    func testOldGenerationTableUpdatesAreIgnoredAfterRestart() async throws {
        let updates = TableUpdateBoundary()
        let engine = HandTrackingEngine(
            isSupported: true,
            runSession: {},
            stopSession: {},
            tableSurfaceUpdates: { updates.makeStream() }
        )

        try await engine.start()
        let old = tableSurface(id: UUID(), x: -0.2, timestamp: 10)
        updates.yield(.added(old), to: 0)
        engine.stop()
        try await engine.start()

        updates.yield(.updated(old.with(timestamp: 10.4)), to: 0)
        await Task.yield()
        XCTAssertNil(engine.tablePlacement)

        let current = tableSurface(id: UUID(), x: 0.2, timestamp: 20)
        updates.yield(.added(current), to: 1)
        updates.yield(.updated(current.with(timestamp: 20.4)), to: 1)
        await waitUntil { engine.tablePlacement != nil }

        XCTAssertEqual(engine.tablePlacement?.transform.translation.x, 0.2)
    }

    // Break caught: a plane-only pause can be promoted to a global hand
    // interruption, pausing or failing every shared tracking experience.
    func testPlaneOnlyProviderPauseInvalidatesTableWithoutInterruptingHands() async throws {
        let tables = TableUpdateBoundary()
        let providers = ProviderStateUpdateBoundary()
        var events: [LiveHandJointSessionEvent] = []
        let engine = HandTrackingEngine(
            isSupported: true,
            runSession: {},
            stopSession: {},
            tableSurfaceUpdates: { tables.makeStream() },
            providerStateUpdates: { providers.makeStream() }
        )
        engine.setEventHandler { event, _ in events.append(event) }

        try await engine.start()
        let surface = tableSurface(id: UUID(), x: 0.1, timestamp: 10)
        tables.yield(.added(surface), to: 0)
        tables.yield(.updated(surface.with(timestamp: 10.4)), to: 0)
        await waitUntil { engine.tablePlacement != nil }

        providers.yield(TrackingProviderStateUpdate(
            roles: [.plane],
            state: .paused,
            timestamp: 10.5,
            failureMessage: nil
        ), to: 0)
        await waitUntil { engine.tablePlacement == nil }

        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(events.isEmpty)
    }

    // Break caught: provider-specific filtering can accidentally suppress
    // the existing hand/world interruption and fatal-stop semantics.
    func testHandAndWorldProviderTransitionsRemainSessionEvents() async throws {
        let providers = ProviderStateUpdateBoundary()
        var events: [LiveHandJointSessionEvent] = []
        let engine = HandTrackingEngine(
            isSupported: true,
            runSession: {},
            stopSession: {},
            providerStateUpdates: { providers.makeStream() }
        )
        engine.setEventHandler { event, _ in events.append(event) }
        try await engine.start()

        providers.yield(TrackingProviderStateUpdate(
            roles: [.hand],
            state: .paused,
            timestamp: 20,
            failureMessage: nil
        ), to: 0)
        providers.yield(TrackingProviderStateUpdate(
            roles: [.world],
            state: .stopped,
            timestamp: 20.1,
            failureMessage: "World provider stopped"
        ), to: 0)
        await waitUntil { events.count == 2 }

        XCTAssertEqual(events, [
            .interrupted,
            .providerFailed("World provider stopped")
        ])
    }

    private func tableSurface(
        id: UUID,
        x: Float,
        timestamp: TimeInterval
    ) -> DetectedTableSurface {
        DetectedTableSurface(
            id: id,
            timestamp: timestamp,
            transform: simd_float4x4(translation: [x, 0.73, -0.55]),
            extent: [1, 0.7],
            isTracked: true
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}

@MainActor
private final class TableUpdateBoundary {
    private var continuations: [Int: AsyncStream<TableSurfaceUpdate>.Continuation] = [:]
    private var nextID = 0

    func makeStream() -> AsyncStream<TableSurfaceUpdate> {
        let id = nextID
        nextID += 1
        return AsyncStream { continuation in
            continuations[id] = continuation
        }
    }

    func yield(_ update: TableSurfaceUpdate, to id: Int) {
        continuations[id]?.yield(update)
    }
}

@MainActor
private final class ProviderStateUpdateBoundary {
    private var continuations: [Int: AsyncStream<TrackingProviderStateUpdate>.Continuation] = [:]
    private var nextID = 0

    func makeStream() -> AsyncStream<TrackingProviderStateUpdate> {
        let id = nextID
        nextID += 1
        return AsyncStream { continuation in
            continuations[id] = continuation
        }
    }

    func yield(_ update: TrackingProviderStateUpdate, to id: Int) {
        continuations[id]?.yield(update)
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
