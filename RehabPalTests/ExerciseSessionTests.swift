import XCTest
@testable import RehabPal

final class ExerciseSessionTests: XCTestCase {
    @MainActor func testMovingHoleScheduleHasEightSafeTargetsAcrossAllQuadrants() {
        let schedule = BalanceTargetSchedule(seed: 42)
        XCTAssertEqual(schedule.targets.count, 8)
        for quadrant in BalanceQuadrant.allCases {
            XCTAssertEqual(schedule.targets.filter { $0.quadrant == quadrant }.count, 2)
        }
        XCTAssertTrue(schedule.targets.allSatisfy { abs($0.x) <= 0.21 && abs($0.z) <= 0.135 })
        XCTAssertFalse(zip(schedule.targets, schedule.targets.dropFirst()).contains { $0.quadrant == $1.quadrant })
        XCTAssertEqual(schedule, BalanceTargetSchedule(seed: 42))
    }

    @MainActor func testMovingHoleRequiresContinuousDwellAndPausesWhenTrackingIsLost() {
        var session = MovingHoleBalanceSession(seed: 7, requiredRepetitions: 2, dwellSeconds: 0.5)
        XCTAssertFalse(session.update(ballPosition: session.currentTarget.position, at: 0, isTracked: true))
        XCTAssertFalse(session.update(ballPosition: session.currentTarget.position, at: 0.3, isTracked: false))
        XCTAssertFalse(session.update(ballPosition: session.currentTarget.position, at: 0.6, isTracked: true))
        XCTAssertFalse(session.update(ballPosition: session.currentTarget.position, at: 1.11, isTracked: true))
        XCTAssertEqual(session.completedRepetitions, 1)
    }

    func testBalanceScheduleDistributesEveryDirectionEqually() {
        for corrections in 1...4 {
            let schedule = BalanceSchedule(correctionsPerDirection: corrections, shuffle: false)
            for direction in WristDirection.allCases {
                XCTAssertEqual(schedule.directions.filter { $0 == direction }.count, corrections)
            }
        }
    }

    func testBalanceCompletesOnlyPrescribedHeldCorrections() {
        var session = BalanceSession(correctionsPerDirection: 1, requiredHoldSeconds: 0.8, shuffle: false)
        XCTAssertFalse(session.registerCentreHold(seconds: 0.7, isTracked: true))
        XCTAssertEqual(session.completedCorrections, 0)
        for index in 0..<4 {
            let finished = session.registerCentreHold(seconds: 0.8, isTracked: true)
            XCTAssertEqual(finished, index == 3)
        }
        XCTAssertTrue(session.isComplete)
    }

    func testExerciseSessionsDoNotProgressWhileTrackingIsLost() {
        var balance = BalanceSession(correctionsPerDirection: 1, requiredHoldSeconds: 0.8, shuffle: false)
        XCTAssertFalse(balance.registerCentreHold(seconds: 2, isTracked: false))
        XCTAssertEqual(balance.completedCorrections, 0)

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
}
