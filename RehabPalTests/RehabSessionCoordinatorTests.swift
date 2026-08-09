import XCTest
import simd
@testable import RehabPal

final class RehabSessionCoordinatorTests: XCTestCase {
    @MainActor
    func testRequestsCarryThePrescriptionAffectedHandAndTypedGoal() {
        let prescription = Prescription.demo

        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: prescription,
            goal: prescription.squeezeRepetitions
        )

        XCTAssertEqual(request.experience, .exercise(.squeeze))
        XCTAssertEqual(request.affectedHand, .right)
        XCTAssertEqual(request.goal, 5)
    }

    @MainActor
    func testCoordinatorRejectsARequestForAnyHandOtherThanThePrescription() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            affectedHand: .left,
            goal: 10
        )

        await coordinator.startLive(request)

        XCTAssertEqual(
            coordinator.phase,
            .failed(SessionFailure(
                request: request,
                reason: .affectedHandMismatch(expected: .right, received: .left),
                recoveryActions: [.cancel]
            ))
        )
        XCTAssertEqual(live.startCount, 0)
    }

    @MainActor
    func testLiveStartupPublishesTypedProgressAndLiveOutcomeProvenance() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: .demo,
            goal: 5
        )

        await coordinator.startLive(request)
        XCTAssertTrue(coordinator.shouldMonitorFrames)
        coordinator.accept(SessionProgress(completed: 5, goal: 5, partial: 0))
        let result = GameplayResult(
            exercise: .squeeze,
            prescribedDose: 5,
            completedDose: 5,
            trackingNote: "Measured from affected-hand joints"
        )
        let outcome = coordinator.finish(with: .gameplay(result))

        XCTAssertEqual(live.startCount, 1)
        XCTAssertEqual(outcome?.request, request)
        XCTAssertEqual(outcome?.progress, SessionProgress(completed: 5, goal: 5, partial: 0))
        XCTAssertEqual(outcome?.provenance, .live)
        XCTAssertEqual(outcome?.payload, .gameplay(result))
        if let outcome {
            XCTAssertEqual(coordinator.phase, .completed(outcome))
        }
        XCTAssertFalse(coordinator.shouldMonitorFrames)
    }

    @MainActor
    func testLiveFailureOffersRetryAndExplicitDemoWithoutSwitchingSilently() async {
        let live = TestLiveJointSource(startResults: [.failure(TestLiveError.denied)])
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo,
            goal: 10
        )

        await coordinator.startLive(request)

        guard case let .failed(failure) = coordinator.phase else {
            return XCTFail("Expected a recoverable live-start failure")
        }
        XCTAssertEqual(failure.request, request)
        XCTAssertEqual(failure.reason, .liveStartupFailed("Tracking permission was denied"))
        XCTAssertEqual(failure.recoveryActions, [.retryLive, .enterDemoMode, .cancel])
        XCTAssertNil(coordinator.provenance)
        XCTAssertFalse(coordinator.isUsingDemoMode)
        XCTAssertFalse(coordinator.shouldMonitorFrames)
    }

    @MainActor
    func testRetryAttemptsLiveAgainAndExplicitDemoIsMarkedSimulated() async {
        let live = TestLiveJointSource(startResults: [
            .failure(TestLiveError.denied),
            .success(())
        ])
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .wristAssessment,
            prescription: .demo,
            goal: 10
        )

        await coordinator.startLive(request)
        let failedMonitoringGeneration = coordinator.monitoringGeneration
        await coordinator.retryLive()
        XCTAssertEqual(coordinator.provenance, .live)
        XCTAssertEqual(live.startCount, 2)
        XCTAssertGreaterThan(
            coordinator.monitoringGeneration,
            failedMonitoringGeneration
        )

        coordinator.cancel()
        let alwaysFailing = TestLiveJointSource(startResults: [.failure(TestLiveError.denied)])
        let demoCoordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: alwaysFailing)
        await demoCoordinator.startLive(request)
        XCTAssertTrue(demoCoordinator.startDemoMode())
        XCTAssertEqual(demoCoordinator.provenance, .demo)
        XCTAssertTrue(demoCoordinator.isUsingDemoMode)
        XCTAssertEqual(demoCoordinator.currentFrame?.hand, .right)
        XCTAssertFalse(demoCoordinator.shouldMonitorFrames)
        demoCoordinator.accept(SessionProgress(completed: 10, goal: 10, partial: 0))
        let demoOutcome = demoCoordinator.finish(
            with: .wristAssessment(AssessmentResult.fixture.wrist)
        )
        XCTAssertEqual(demoOutcome?.provenance, .demo)
        XCTAssertEqual(demoOutcome?.provenance.isSimulated, true)
    }

    @MainActor
    func testTrackingLossPreservesCompletedWorkDiscardsPartialAndRequiresRecalibrationAfterTwoSeconds() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: .demo,
            goal: 5
        )
        await coordinator.startLive(request)
        coordinator.accept(SessionProgress(completed: 2, goal: 5, partial: 0.75))

        coordinator.receiveJointFrame(nil, at: 4)

        XCTAssertEqual(
            coordinator.phase,
            .paused(
                request: request,
                progress: SessionProgress(completed: 2, goal: 5, partial: 0),
                reason: .trackingLost(requiresRecalibration: false)
            )
        )
        XCTAssertEqual(coordinator.provenance, .live)
        XCTAssertEqual(
            coordinator.authorization,
            ActiveRehabSession(request: request, provenance: .live)
        )

        coordinator.receiveJointFrame(trackedFrame(hand: .right, at: 6.1), at: 6.1)
        XCTAssertEqual(coordinator.pauseReason, .trackingLost(requiresRecalibration: true))
        XCTAssertTrue(coordinator.confirmRecalibration())
        XCTAssertEqual(coordinator.progress, SessionProgress(completed: 2, goal: 5, partial: 0))
        XCTAssertNil(coordinator.pauseReason)
    }

    @MainActor
    func testWrongHandFramesCannotResumeTheAffectedHandSession() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .handAssessment,
            prescription: .demo,
            goal: 10
        )
        await coordinator.startLive(request)

        coordinator.receiveJointFrame(trackedFrame(hand: .left, at: 1), at: 1)

        XCTAssertEqual(coordinator.pauseReason, .trackingLost(requiresRecalibration: false))
        XCTAssertNil(coordinator.latestAcceptedJointFrame)
    }

    @MainActor
    func testCurrentFrameAndCompatibilityObservationNeverBypassAffectedHandAcceptance() async {
        let live = TestLiveJointSource()
        live.latestJointFrame = trackedFrame(hand: .left, at: 1)
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo,
            goal: 10
        )
        await coordinator.startLive(request)

        XCTAssertNil(coordinator.currentFrame)
        XCTAssertFalse(coordinator.compatibilityObservation.isTracked)

        coordinator.receiveJointFrame(live.latestJointFrame, at: 1)
        XCTAssertNil(coordinator.currentFrame)
        XCTAssertFalse(coordinator.compatibilityObservation.isTracked)

        let affectedFrame = trackedFrame(hand: .right, at: 2)
        coordinator.receiveJointFrame(affectedFrame, at: 2)
        XCTAssertEqual(coordinator.currentFrame?.hand, .right)
        XCTAssertEqual(coordinator.currentFrame?.timestamp, 2)
        XCTAssertTrue(coordinator.compatibilityObservation.isTracked)
        XCTAssertEqual(coordinator.compatibilityObservation.timestamp, 2)
    }

    @MainActor
    func testCancelStopsTrackingAndClearsTheActiveSession() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo,
            goal: 10
        )
        await coordinator.startLive(request)
        coordinator.receiveJointFrame(nil, at: 1)

        coordinator.cancel()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(live.stopCount, 1)
        XCTAssertNil(coordinator.activeRequest)
        XCTAssertNil(coordinator.latestAcceptedJointFrame)
    }

    @MainActor
    func testAppStateRoutesMatchingTypedOutcomesAndRetainsProvenance() async throws {
        let state = AppState()
        XCTAssertTrue(state.startRoutine())
        XCTAssertTrue(state.answerMedication(taken: true))
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: state.prescription, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: state.prescription,
            goal: 10
        )
        await coordinator.startLive(request)
        coordinator.accept(SessionProgress(completed: 10, goal: 10, partial: 0))
        let result = GameplayResult(
            exercise: .balance,
            prescribedDose: 10,
            completedDose: 10,
            trackingNote: "Measured"
        )
        let outcome = try XCTUnwrap(coordinator.finish(with: .gameplay(result)))

        XCTAssertTrue(state.activateSession(request, provenance: .live))
        XCTAssertTrue(state.route(outcome))
        XCTAssertEqual(state.exerciseResults[.balance], result)
        XCTAssertEqual(state.sessionOutcomes[.exercise(.balance)]?.provenance, .live)
        XCTAssertFalse(state.route(outcome))
    }

    @MainActor
    func testAppStateRejectsOutcomeForAHandOtherThanThePrescription() {
        let state = AppState()
        XCTAssertTrue(state.startRoutine())
        XCTAssertTrue(state.answerMedication(taken: true))
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            affectedHand: .left,
            goal: 10
        )
        let progress = SessionProgress(completed: 10, goal: 10, partial: 0)
        let outcome = RehabSessionOutcome(
            request: request,
            progress: progress,
            provenance: .live,
            payload: .gameplay(GameplayResult(
                exercise: .balance,
                prescribedDose: 10,
                completedDose: 10,
                trackingNote: "Wrong hand"
            ))
        )

        XCTAssertFalse(state.route(outcome))
        XCTAssertTrue(state.exerciseResults.isEmpty)
    }

    @MainActor
    func testAppStateRejectsOutcomesWithoutTheActiveRequestAndProvenance() {
        let state = AppState()
        XCTAssertTrue(state.startRoutine())
        XCTAssertTrue(state.answerMedication(taken: true))
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: state.prescription,
            goal: 10
        )
        let progress = SessionProgress(completed: 10, goal: 10, partial: 0)
        let result = GameplayResult(
            exercise: .balance,
            prescribedDose: 10,
            completedDose: 10,
            trackingNote: "Measured"
        )
        let liveOutcome = RehabSessionOutcome(
            request: request,
            progress: progress,
            provenance: .live,
            payload: .gameplay(result)
        )

        XCTAssertFalse(state.route(liveOutcome))
        XCTAssertTrue(state.activateSession(request, provenance: .live))

        let demoOutcome = RehabSessionOutcome(
            request: request,
            progress: progress,
            provenance: .demo,
            payload: .gameplay(result)
        )
        XCTAssertFalse(state.route(demoOutcome))
        XCTAssertTrue(state.exerciseResults.isEmpty)
    }

    private func trackedFrame(hand: AffectedHand, at timestamp: TimeInterval) -> HandJointFrame {
        .synthetic(
            hand: hand,
            timestamp: timestamp,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )
    }
}

@MainActor
private final class TestLiveJointSource: LiveHandJointSession {
    var isSupported = true
    var latestJointFrame: HandJointFrame?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var startResults: [Result<Void, Error>]

    init(startResults: [Result<Void, Error>] = [.success(())]) {
        self.startResults = startResults
    }

    func start() async throws {
        let index = min(startCount, startResults.count - 1)
        startCount += 1
        try startResults[index].get()
    }

    func stop() {
        stopCount += 1
    }
}

private enum TestLiveError: LocalizedError {
    case denied

    var errorDescription: String? { "Tracking permission was denied" }
}
