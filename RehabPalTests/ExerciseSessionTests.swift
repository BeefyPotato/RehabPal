import XCTest
@testable import RehabPal

final class ExerciseSessionTests: XCTestCase {
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
