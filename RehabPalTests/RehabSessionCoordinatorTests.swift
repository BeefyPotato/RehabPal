import XCTest
import simd
@testable import RehabPal

final class RehabSessionCoordinatorTests: XCTestCase {
    @MainActor
    func testRequestsCarryThePrescriptionAffectedHandAndTypedGoal() {
        let prescription = Prescription.demo

        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: prescription
        )

        XCTAssertEqual(request.experience, .exercise(.squeeze))
        XCTAssertEqual(request.affectedHand, .right)
        XCTAssertEqual(request.goal, 5)
    }

    @MainActor
    func testSharedDiagnosticGoalContractReturnsOnlyExactValidatedAttempts() {
        let wrist = RehabSessionRequest(
            experience: .wristAssessment,
            prescription: .demo
        )
        let malformedHand = RehabSessionRequest(
            experience: .handAssessment,
            affectedHand: .right,
            goal: 6
        )
        let exercise = RehabSessionRequest(
            experience: .exercise(.balance),
            affectedHand: .right,
            goal: 6
        )

        XCTAssertTrue(wrist.hasValidGoal)
        XCTAssertEqual(wrist.diagnosticAttemptsPerSubject, 2)
        XCTAssertFalse(malformedHand.hasValidGoal)
        XCTAssertNil(malformedHand.diagnosticAttemptsPerSubject)
        XCTAssertTrue(exercise.hasValidGoal)
        XCTAssertNil(exercise.diagnosticAttemptsPerSubject)
    }

    // Break caught: a one-attempt-per-subject prescription can complete while
    // every resulting digit summary is guaranteed to be unavailable.
    @MainActor
    func testDiagnosticGoalRequiresAtLeastTwoAttemptsPerSubject() {
        let oneAttemptWrist = RehabSessionRequest(
            experience: .wristAssessment,
            affectedHand: .right,
            goal: 5
        )
        let twoAttemptHand = RehabSessionRequest(
            experience: .handAssessment,
            affectedHand: .right,
            goal: 10
        )

        XCTAssertFalse(oneAttemptWrist.hasValidGoal)
        XCTAssertNil(oneAttemptWrist.diagnosticAttemptsPerSubject)
        XCTAssertTrue(twoAttemptHand.hasValidGoal)
        XCTAssertEqual(twoAttemptHand.diagnosticAttemptsPerSubject, 2)
    }

    @MainActor
    func testCoordinatorPublishesTheCurrentViewerPositionFromLiveTracking() {
        let live = TestLiveJointSource()
        live.viewerPosition = SIMD3<Float>(0.2, 1.3, -0.1)
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)

        XCTAssertEqual(coordinator.currentViewerPosition, SIMD3<Float>(0.2, 1.3, -0.1))
    }

    @MainActor
    func testCoordinatorDoesNotInventViewerPoseInDemoMode() async {
        let live = TestLiveJointSource(startResults: [.failure(TestLiveError.denied)])
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: .demo
        )

        await coordinator.startLiveForTesting(request)
        XCTAssertNil(coordinator.currentViewerPosition)
        XCTAssertTrue(coordinator.startDemoMode())
        XCTAssertNil(coordinator.currentViewerPosition)
    }

    // Break caught: the coordinator could hide the app-owned table selected by
    // shared live tracking or leave it visible after the session is cancelled.
    @MainActor
    func testLiveSheepDropExposesDetectedTableUntilCancel() async {
        let live = TestLiveJointSource()
        live.tablePlacement = TablePlacement(
            transform: simd_float4x4(translation: [0.1, 0.74, -0.5]),
            source: .detected
        )
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.sheepDrop),
            prescription: .demo
        )

        await coordinator.startLiveForTesting(request)

        XCTAssertEqual(coordinator.currentTablePlacement, live.tablePlacement)
        coordinator.cancel()
        XCTAssertNil(coordinator.currentTablePlacement)
    }

    // Break caught: entering explicit Demo Mode could start live tracking or
    // omit the deterministic estimated table needed without ARKit.
    @MainActor
    func testDemoSheepDropPublishesEstimatedTableWithoutStartingLiveTracking() async {
        let live = TestLiveJointSource()
        live.isSupported = false
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.sheepDrop),
            prescription: .demo
        )

        await coordinator.startLiveForTesting(request)
        XCTAssertTrue(coordinator.startDemoMode())

        XCTAssertEqual(live.startCount, 0)
        XCTAssertEqual(coordinator.currentTablePlacement?.source, .estimated)
        XCTAssertEqual(
            coordinator.currentTablePlacement?.transform.translation,
            [0, 0.73, -0.55]
        )
        let frame = coordinator.currentFrame
        XCTAssertEqual(frame?.confidence(requiring: SheepDropSession.requiredJoints), .good)
        XCTAssertGreaterThanOrEqual(
            FiveFingertipPose(frame: try! XCTUnwrap(frame), sheepPosition: .zero)?.clusterRatio ?? 0,
            SheepDropSession.releaseClusterRatio
        )
    }

    // Mutation caught: retaining the old fingertip contract globally pauses
    // targeted drag when a non-wrist joint is obscured.
    @MainActor
    func testSheepDropGlobalPresenceRequiresOnlyAffectedWrist() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .exercise(.sheepDrop),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)

        let usable = sheepDropFrame(hand: .right, at: 1, pose: .open)
        coordinator.receiveJointFrame(usable, at: 1)

        XCTAssertNil(coordinator.pauseReason)
        XCTAssertEqual(coordinator.currentFrame?.timestamp, 1)

        var missingTipJoints = sheepDropFrame(
            hand: .right,
            at: 1.1,
            pose: .open
        ).joints
        missingTipJoints[.littleFingerTip] = .untracked
        coordinator.receiveJointFrame(
            .synthetic(hand: .right, timestamp: 1.1, joints: missingTipJoints),
            at: 1.1
        )

        XCTAssertNil(coordinator.pauseReason)
        XCTAssertEqual(coordinator.currentFrame?.timestamp, 1.1)
    }

    // Mutation caught: retaining five-tip calibration makes long-loss recovery
    // impossible for the targeted-drag route despite a fresh affected wrist.
    @MainActor
    func testSheepDropCalibrationAcceptsFreshAffectedWristAfterLongLoss() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .exercise(.sheepDrop),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        coordinator.receiveJointFrame(
            sheepDropFrame(hand: .right, at: 1, pose: .open),
            at: 1
        )
        coordinator.receiveJointFrame(nil, at: 2)
        let wrist = HandJointSample.tracked(transform: matrix_identity_float4x4)
        coordinator.receiveJointFrame(.synthetic(
            hand: .left,
            timestamp: 4.1,
            joints: [.wrist: wrist]
        ), at: 4.1)

        let generation = try! XCTUnwrap(coordinator.pendingProcessorResetGeneration)
        XCTAssertFalse(coordinator.acknowledgeProcessorReset(generation + 1))
        XCTAssertTrue(coordinator.acknowledgeProcessorReset(generation))
        XCTAssertFalse(coordinator.acknowledgeProcessorReset(generation))
        XCTAssertFalse(coordinator.acknowledgeProcessorCalibration(
            generation: generation,
            frameTimestamp: 4.1
        ))
        XCTAssertFalse(coordinator.canConfirmRecalibration)

        coordinator.receiveJointFrame(.synthetic(
            hand: .right,
            timestamp: 4.2,
            joints: [.wrist: wrist]
        ), at: 4.2)
        XCTAssertTrue(coordinator.acknowledgeProcessorCalibration(
            generation: generation,
            frameTimestamp: 4.2
        ))
        XCTAssertTrue(coordinator.canConfirmRecalibration)
        XCTAssertTrue(coordinator.confirmRecalibration())
    }

    // Break caught: the Sheep Drop route can finish with another exercise's
    // gameplay result when both doses happen to match.
    @MainActor
    func testSheepDropCompletionAcceptsOnlyMatchingGameplayResult() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .exercise(.sheepDrop),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        coordinator.accept(SessionProgress(completed: 5, goal: 5, partial: 0))

        XCTAssertNil(coordinator.finish(with: .gameplay(GameplayResult(
            exercise: .squeeze,
            prescribedDose: 5,
            completedDose: 5,
            trackingNote: "wrong route"
        ))))
        let sheepResult = GameplayResult(
            exercise: .sheepDrop,
            prescribedDose: 5,
            completedDose: 5,
            trackingNote: "five-fingertip joint observations"
        )
        XCTAssertEqual(
            coordinator.finish(with: .gameplay(sheepResult))?.payload,
            .gameplay(sheepResult)
        )
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

        await coordinator.startLiveForTesting(request)

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
    func testCoordinatorRejectsDiagnosticGoalThatCannotBeDistributedAcrossFiveTargets() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .wristAssessment,
            affectedHand: .right,
            goal: 6
        )

        await coordinator.startLiveForTesting(request)

        XCTAssertEqual(
            coordinator.phase,
            .failed(SessionFailure(
                request: request,
                reason: .invalidGoal,
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
            prescription: .demo
        )

        await coordinator.startLiveForTesting(request)
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
    func testLiveStartupRestartsFrameMonitorAfterStartingPhase() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )

        let token = try! XCTUnwrap(coordinator.prepareLiveStart(request))
        let startingGeneration = coordinator.monitoringGeneration

        XCTAssertFalse(coordinator.shouldMonitorFrames)
        let started = await coordinator.startPreparedLive(token)
        XCTAssertTrue(started)
        XCTAssertTrue(coordinator.shouldMonitorFrames)
        XCTAssertGreaterThan(coordinator.monitoringGeneration, startingGeneration)
    }

    @MainActor
    func testLiveFailureOffersRetryAndExplicitDemoWithoutSwitchingSilently() async {
        let live = TestLiveJointSource(startResults: [.failure(TestLiveError.denied)])
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )

        await coordinator.startLiveForTesting(request)

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
            prescription: .demo
        )

        await coordinator.startLiveForTesting(request)
        let failedMonitoringGeneration = coordinator.monitoringGeneration
        await coordinator.retryLiveForTesting()
        XCTAssertEqual(coordinator.provenance, .live)
        XCTAssertEqual(live.startCount, 2)
        XCTAssertGreaterThan(
            coordinator.monitoringGeneration,
            failedMonitoringGeneration
        )

        coordinator.cancel()
        let alwaysFailing = TestLiveJointSource(startResults: [.failure(TestLiveError.denied)])
        let demoCoordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: alwaysFailing)
        await demoCoordinator.startLiveForTesting(request)
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
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
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
        let generation = coordinator.pendingProcessorResetGeneration
        XCTAssertNotNil(generation)
        XCTAssertFalse(coordinator.confirmRecalibration())
        XCTAssertTrue(coordinator.acknowledgeProcessorReset(generation!))
        XCTAssertNil(coordinator.pendingProcessorResetGeneration)
        XCTAssertFalse(coordinator.confirmRecalibration())
        XCTAssertTrue(coordinator.acknowledgeProcessorCalibration(
            generation: generation!,
            frameTimestamp: 6.1
        ))
        XCTAssertTrue(coordinator.confirmRecalibration())
        XCTAssertEqual(coordinator.progress, SessionProgress(completed: 2, goal: 5, partial: 0))
        XCTAssertNil(coordinator.pauseReason)
    }

    // Break caught: the Balance view can acknowledge long-loss calibration
    // from a replayed retained frame, or reset the processor more than once.
    @MainActor
    func testBalanceLongLossLifecycleRequires25UniqueFramesAndAcknowledgesTheFinalTimestamp() async throws {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        var game = BalanceSession(prescription: .demo, seed: 5)
        var viewState = BalanceViewTrackingState()

        coordinator.updateRequiredJoints(game.requiredJoints)
        coordinator.receiveJointFrame(trackedFrame(hand: .right, at: 1), at: 1)
        coordinator.receiveJointFrame(nil, at: 2)
        coordinator.receiveJointFrame(trackedFrame(hand: .right, at: 4.1), at: 4.1)

        let generation = try XCTUnwrap(coordinator.pendingProcessorResetGeneration)
        XCTAssertTrue(viewState.beginProcessorReset(generation: generation))
        game.pause(requiresRecalibration: true)
        XCTAssertTrue(coordinator.acknowledgeProcessorReset(generation))
        XCTAssertFalse(viewState.beginProcessorReset(generation: generation))
        XCTAssertFalse(coordinator.acknowledgeProcessorReset(generation))

        for index in 0..<25 {
            let timestamp = 5 + Double(index) / 60
            let frame = trackedFrame(hand: .right, at: timestamp)
            coordinator.receiveJointFrame(frame, at: timestamp)
            coordinator.updateRequiredJoints(game.requiredJoints)
            guard let fresh = viewState.consume(frame) else {
                return XCTFail("Expected unique calibration frame \(index + 1)")
            }
            _ = game.process(
                frame: fresh,
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            )
            XCTAssertNil(viewState.consume(frame))
        }

        XCTAssertTrue(game.isCalibrated)
        XCTAssertEqual(game.requiredJoints, [.wrist])
        coordinator.updateRequiredJoints(game.requiredJoints)
        let finalTimestamp = 5 + 24.0 / 60
        var acknowledgementAttempts = 0
        if viewState.takeCalibrationAcknowledgement(generation: generation) {
            acknowledgementAttempts += 1
            XCTAssertTrue(coordinator.acknowledgeProcessorCalibration(
                generation: generation,
                frameTimestamp: finalTimestamp
            ))
        }

        let frame26Timestamp = 5 + 25.0 / 60
        let frame26 = trackedFrame(hand: .right, at: frame26Timestamp)
        coordinator.receiveJointFrame(frame26, at: frame26Timestamp)
        if let fresh = viewState.consume(frame26) {
            _ = game.process(
                frame: fresh,
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            )
        }
        if viewState.takeCalibrationAcknowledgement(generation: generation) {
            acknowledgementAttempts += 1
            _ = coordinator.acknowledgeProcessorCalibration(
                generation: generation,
                frameTimestamp: frame26Timestamp
            )
        }

        XCTAssertEqual(acknowledgementAttempts, 1)
        XCTAssertTrue(coordinator.confirmRecalibration())
    }

    // Break caught: repeatedly polling an old affected-hand frame can keep a
    // session active forever after ARKit has stopped publishing updates.
    @MainActor
    func testStaleAffectedHandFrameIsTrackingLoss() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource(),
            maximumFrameAge: 0.2
        )
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)

        coordinator.receiveJointFrame(trackedFrame(hand: .right, at: 1), at: 1.21)

        XCTAssertEqual(coordinator.pauseReason, .trackingLost(requiresRecalibration: false))
        XCTAssertNil(coordinator.currentFrame)
    }

    // Break caught: chirality alone can accept a frame whose joints are too
    // incomplete for the active processor to use safely.
    @MainActor
    func testNonWristRequiredJointConfidenceFailureDoesNotCauseGlobalTrackingLoss() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        coordinator.updateRequiredJoints(WristNeutralCalibration.requiredJoints)
        var joints = trackedFrame(hand: .right, at: 1).joints
        joints[.littleFingerKnuckle] = .untracked

        coordinator.receiveJointFrame(
            .synthetic(hand: .right, timestamp: 1, joints: joints),
            at: 1
        )

        XCTAssertNil(coordinator.pauseReason)
        XCTAssertNotNil(coordinator.currentFrame)
    }

    // Mutation caught: changing the coordinator presence floor from wrist-only
    // back to the processor's complete joint set globally pauses this session.
    @MainActor
    func testMissingWristStillCausesGlobalTrackingLoss() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        var joints = trackedFrame(hand: .right, at: 1).joints
        joints[.wrist] = .untracked

        coordinator.receiveJointFrame(.synthetic(hand: .right, timestamp: 1, joints: joints), at: 1)

        XCTAssertEqual(coordinator.pauseReason, .trackingLost(requiresRecalibration: false))
        coordinator.receiveJointFrame(.synthetic(hand: .right, timestamp: 3.1, joints: joints), at: 3.1)
        XCTAssertEqual(coordinator.pauseReason, .trackingLost(requiresRecalibration: true))
    }

    // Mutation caught: registering before a successful processor transition
    // lets failed assisted actions inflate the clinical provenance count.
    @MainActor
    func testAssistedProgressCountRegistersOnlySuccessfulTransitionsAndPersistsInOutcome() async throws {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(experience: .exercise(.squeeze), prescription: .demo)
        await coordinator.startLiveForTesting(request)

        XCTAssertFalse(coordinator.registerAssistedProgress(from: 0, to: 0))
        XCTAssertEqual(coordinator.assistedProgressCount, 0)
        XCTAssertTrue(coordinator.registerAssistedProgress(from: 0, to: 1))
        XCTAssertEqual(coordinator.assistedProgressCount, 1)
        coordinator.accept(SessionProgress(completed: request.goal, goal: request.goal, partial: 0))
        let result = GameplayResult(exercise: .squeeze, prescribedDose: request.goal, completedDose: request.goal, trackingNote: "Measured")
        let outcome = try XCTUnwrap(coordinator.finish(with: .gameplay(result)))
        XCTAssertEqual(outcome.assistedProgressCount, 1)
        XCTAssertEqual(coordinator.assistedProgressCount, 1)

        coordinator.cancel()
        XCTAssertEqual(coordinator.assistedProgressCount, 0)
    }

    func testAssistedControlAuthorizationCoversLiveDemoPausedAndDisablesTerminalPhases() {
        let request = RehabSessionRequest(experience: .exercise(.squeeze), prescription: .demo)
        let progress = SessionProgress(completed: 0, goal: request.goal, partial: 0)
        XCTAssertTrue(AssistedProgressControl.isAuthorized(
            .active(request: request, progress: progress, provenance: .live),
            for: request.experience
        ))
        XCTAssertTrue(AssistedProgressControl.isAuthorized(
            .active(request: request, progress: progress, provenance: .demo),
            for: request.experience
        ))
        XCTAssertTrue(AssistedProgressControl.isAuthorized(
            .paused(request: request, progress: progress, reason: .trackingLost(requiresRecalibration: true)),
            for: request.experience
        ))
        XCTAssertFalse(AssistedProgressControl.isAuthorized(.starting(request), for: request.experience))
        XCTAssertFalse(AssistedProgressControl.isAuthorized(.idle, for: request.experience))
        XCTAssertFalse(AssistedProgressControl.isAuthorized(
            .active(
                request: request,
                progress: SessionProgress(completed: request.goal, goal: request.goal, partial: 0),
                provenance: .live
            ),
            for: request.experience
        ))
    }

    // Mutation caught: restricting finish to `.active` strands a valid final
    // assisted processor transition at N/N while tracking recovery is paused.
    @MainActor
    func testFinalAssistedProgressCanFinishFromBriefAndLongTrackingPause() async throws {
        for lossDuration in [0.1, RehabSessionCoordinator.recalibrationDelay + 0.1] {
            let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: TestLiveJointSource())
            let request = RehabSessionRequest(experience: .exercise(.squeeze), prescription: .demo)
            await coordinator.startLiveForTesting(request)
            coordinator.accept(SessionProgress(completed: request.goal - 1, goal: request.goal, partial: 0))
            coordinator.receiveJointFrame(nil, at: 100)
            if lossDuration >= RehabSessionCoordinator.recalibrationDelay {
                coordinator.receiveJointFrame(nil, at: 100 + lossDuration)
            }
            XCTAssertTrue(coordinator.registerAssistedProgress(from: request.goal - 1, to: request.goal))
            coordinator.accept(SessionProgress(completed: request.goal, goal: request.goal, partial: 0))

            let payload = GameplayResult(
                exercise: .squeeze,
                prescribedDose: request.goal,
                completedDose: request.goal,
                trackingNote: "Measured with assisted disclosure"
            )
            let outcome = try XCTUnwrap(coordinator.finish(with: .gameplay(payload)))
            XCTAssertEqual(outcome.provenance, .live)
            XCTAssertEqual(outcome.progress.completed, request.goal)
            XCTAssertEqual(outcome.assistedProgressCount, 1)
            XCTAssertEqual(outcome.payload, .gameplay(payload))
        }
    }

    @MainActor
    func testPausedFinishRejectsNonfinalOrUnregisteredProgressAndNonfinalAssistanceStaysPaused() async {
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: TestLiveJointSource())
        let request = RehabSessionRequest(experience: .exercise(.squeeze), prescription: .demo)
        await coordinator.startLiveForTesting(request)
        coordinator.receiveJointFrame(nil, at: 1)

        XCTAssertTrue(coordinator.registerAssistedProgress(from: 0, to: 1))
        coordinator.accept(SessionProgress(completed: 1, goal: request.goal, partial: 0))
        XCTAssertEqual(coordinator.progress?.completed, 1)
        XCTAssertNotNil(coordinator.pauseReason)
        XCTAssertNil(coordinator.finish(with: .gameplay(GameplayResult(
            exercise: .squeeze,
            prescribedDose: request.goal,
            completedDose: request.goal,
            trackingNote: "Invalid early finish"
        ))))

        coordinator.cancel()
        XCTAssertNil(coordinator.finish(with: .gameplay(GameplayResult(
            exercise: .squeeze,
            prescribedDose: request.goal,
            completedDose: request.goal,
            trackingNote: "Idle finish"
        ))))
    }

    // Break caught: ARKit provider interruption/authorization events can leave
    // a live coordinator active even though no usable frames can arrive.
    @MainActor
    func testLiveProviderAndAuthorizationEventsBecomeLossOrFailure() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)

        live.emit(.interrupted, at: 1)
        XCTAssertEqual(coordinator.pauseReason, .trackingLost(requiresRecalibration: false))

        live.emit(.authorizationDenied, at: 1.1)
        guard case let .failed(failure) = coordinator.phase else {
            return XCTFail("Expected authorization denial to fail the live session")
        }
        XCTAssertEqual(failure.reason, .liveAuthorizationDenied)

        let providerLive = TestLiveJointSource()
        let providerCoordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: providerLive
        )
        await providerCoordinator.startLiveForTesting(request)
        providerLive.emit(.providerFailed("Hand provider stopped"), at: 2)
        guard case let .failed(providerFailure) = providerCoordinator.phase else {
            return XCTFail("Expected provider failure to fail the live session")
        }
        XCTAssertEqual(
            providerFailure.reason,
            .liveProviderFailed("Hand provider stopped")
        )
    }

    // Break caught: after a provider interruption, polling the provider's
    // cached pre-interruption frame can immediately undo the tracking loss.
    @MainActor
    func testProviderInterruptionRejectsCachedFrameUntilANewUpdateArrives() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: live,
            maximumFrameAge: 1
        )
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        live.latestJointFrame = trackedFrame(hand: .right, at: 1)
        coordinator.pollLiveTracking(at: 1)

        live.emit(.interrupted, at: 1.05)
        coordinator.pollLiveTracking(at: 1.1)
        XCTAssertEqual(
            coordinator.pauseReason,
            .trackingLost(requiresRecalibration: false)
        )

        live.latestJointFrame = trackedFrame(hand: .right, at: 1.2)
        coordinator.pollLiveTracking(at: 1.2)
        XCTAssertNil(coordinator.pauseReason)
        XCTAssertEqual(coordinator.currentFrame?.timestamp, 1.2)
    }

    @MainActor
    func testWrongHandFramesCannotResumeTheAffectedHandSession() async {
        let live = TestLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .handAssessment,
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)

        coordinator.receiveJointFrame(trackedFrame(hand: .left, at: 1), at: 1)

        XCTAssertEqual(coordinator.pauseReason, .trackingLost(requiresRecalibration: false))
        XCTAssertNil(coordinator.latestAcceptedJointFrame)
    }

    @MainActor
    func testCoordinatorBuffersEveryDiagnosticObservationUntilConsumed() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .handAssessment,
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)

        coordinator.receiveJointFrame(nil, at: 1)
        coordinator.receiveJointFrame(trackedFrame(hand: .right, at: 1.05), at: 1.05)

        let observations = coordinator.consumeDiagnosticObservations()
        XCTAssertEqual(observations.count, 2)
        XCTAssertNil(observations[0].frame)
        XCTAssertEqual(observations[1].frame?.timestamp, 1.05)
        XCTAssertLessThan(observations[0].sequence, observations[1].sequence)
        XCTAssertTrue(coordinator.consumeDiagnosticObservations().isEmpty)
    }

    // Break caught: if RealityKit stops rendering while monitoring continues,
    // the diagnostic observation queue can grow without limit.
    @MainActor
    func testCoordinatorBoundsDiagnosticObservationQueue() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .handAssessment,
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)

        for index in 0..<(RehabSessionCoordinator.maximumPendingDiagnosticObservations + 20) {
            coordinator.receiveJointFrame(nil, at: Double(index) / 20)
        }

        let observations = coordinator.consumeDiagnosticObservations()
        XCTAssertEqual(
            observations.count,
            RehabSessionCoordinator.maximumPendingDiagnosticObservations
        )
        XCTAssertGreaterThan(observations.first?.sequence ?? 0, 1)
    }

    // Break caught: identical render-cadence progress and pause publications
    // can trigger observation writes even though user-visible state is unchanged.
    @MainActor
    func testCoordinatorDeduplicatesIdenticalProgressAndPauseState() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        let progress = SessionProgress(completed: 1, goal: 5, partial: 0.5)

        coordinator.accept(progress)
        let activeRevision = coordinator.phaseRevision
        coordinator.accept(progress)
        XCTAssertEqual(coordinator.phaseRevision, activeRevision)

        coordinator.receiveJointFrame(nil, at: 1)
        let pausedRevision = coordinator.phaseRevision
        coordinator.receiveJointFrame(nil, at: 1.05)
        XCTAssertEqual(coordinator.phaseRevision, pausedRevision)
    }

    // Break caught: a cancelled/superseded start can publish A's completion or
    // stop tracking after request B has already become active.
    @MainActor
    func testSupersededDelayedStartCannotMutateOrStopNewerSession() async {
        let live = DelayedLiveJointSource()
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let requestA = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        let requestB = RehabSessionRequest(
            experience: .exercise(.squeeze),
            prescription: .demo
        )

        let tokenA = try! XCTUnwrap(coordinator.prepareLiveStart(requestA))
        let startA = Task { await coordinator.startPreparedLive(tokenA) }
        await live.waitForStartCount(1)

        let tokenB = try! XCTUnwrap(coordinator.prepareLiveStart(requestB))
        let startB = Task { await coordinator.startPreparedLive(tokenB) }
        await live.waitForStartCount(2)
        live.succeedStart(1)
        _ = await startB.value
        XCTAssertEqual(coordinator.activeRequest, requestB)

        live.succeedStart(0)
        _ = await startA.value
        XCTAssertEqual(coordinator.activeRequest, requestB)
        XCTAssertEqual(coordinator.provenance, .live)
        XCTAssertEqual(live.stopCount, 1)
    }

    @MainActor
    func testWristCompletionRemainsPendingUntilCoordinatorResumes() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .wristAssessment,
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        coordinator.receiveJointFrame(nil, at: 1)
        var delivery = DiagnosticCompletionDelivery()

        delivery.attempt {
            coordinator.finish(with: .wristAssessment(AssessmentResult.fixture.wrist)) != nil
        }
        XCTAssertFalse(delivery.isFinished)

        coordinator.receiveJointFrame(trackedFrame(hand: .right, at: 1.1), at: 1.1)
        coordinator.accept(SessionProgress(completed: 10, goal: 10, partial: 0))
        delivery.attempt {
            coordinator.finish(with: .wristAssessment(AssessmentResult.fixture.wrist)) != nil
        }

        XCTAssertTrue(delivery.isFinished)
        guard case .completed = coordinator.phase else {
            return XCTFail("Expected the retained wrist completion to finish after resume")
        }
    }

    @MainActor
    func testFingerCompletionRemainsPendingUntilCoordinatorResumes() async {
        let coordinator = RehabSessionCoordinator(
            prescription: .demo,
            liveTracking: TestLiveJointSource()
        )
        let request = RehabSessionRequest(
            experience: .handAssessment,
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        coordinator.receiveJointFrame(nil, at: 1)
        var delivery = DiagnosticCompletionDelivery()

        delivery.attempt {
            coordinator.finish(with: .handAssessment(AssessmentResult.fixture.handROM)) != nil
        }
        XCTAssertFalse(delivery.isFinished)

        coordinator.receiveJointFrame(trackedFrame(hand: .right, at: 1.1), at: 1.1)
        coordinator.accept(SessionProgress(completed: 10, goal: 10, partial: 0))
        delivery.attempt {
            coordinator.finish(with: .handAssessment(AssessmentResult.fixture.handROM)) != nil
        }

        XCTAssertTrue(delivery.isFinished)
        guard case .completed = coordinator.phase else {
            return XCTFail("Expected the retained finger completion to finish after resume")
        }
    }

    @MainActor
    func testCurrentFrameAndCompatibilityObservationNeverBypassAffectedHandAcceptance() async {
        let live = TestLiveJointSource()
        live.latestJointFrame = trackedFrame(hand: .left, at: 1)
        let coordinator = RehabSessionCoordinator(prescription: .demo, liveTracking: live)
        let request = RehabSessionRequest(
            experience: .exercise(.balance),
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)

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
            prescription: .demo
        )
        await coordinator.startLiveForTesting(request)
        coordinator.receiveJointFrame(nil, at: 1)

        coordinator.cancel()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(live.stopCount, 1)
        XCTAssertNil(coordinator.activeRequest)
        XCTAssertNil(coordinator.latestAcceptedJointFrame)
        XCTAssertTrue(coordinator.consumeDiagnosticObservations().isEmpty)
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
            prescription: state.prescription
        )
        await coordinator.startLiveForTesting(request)
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
            prescription: state.prescription
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
            joints: Dictionary(uniqueKeysWithValues: HandJoint.allCases.map {
                ($0, HandJointSample.tracked(transform: matrix_identity_float4x4))
            })
        )
    }

    private enum SheepDropTestPose {
        case open
        case clustered
    }

    private func sheepDropFrame(
        hand: AffectedHand,
        at timestamp: TimeInterval,
        pose: SheepDropTestPose
    ) -> HandJointFrame {
        let center = SIMD3<Float>(0.335, 0.12, 0)
        var joints: [HandJoint: HandJointSample] = [
            .wrist: .tracked(transform: simd_float4x4(
                translation: center + SIMD3<Float>(0, -0.08, 0)
            )),
            .indexFingerKnuckle: .tracked(transform: simd_float4x4(
                translation: center + SIMD3<Float>(-0.03, -0.02, 0)
            )),
            .middleFingerKnuckle: .tracked(transform: simd_float4x4(
                translation: center + SIMD3<Float>(-0.01, -0.02, 0)
            )),
            .ringFingerKnuckle: .tracked(transform: simd_float4x4(
                translation: center + SIMD3<Float>(0.01, -0.02, 0)
            )),
            .littleFingerKnuckle: .tracked(transform: simd_float4x4(
                translation: center + SIMD3<Float>(0.03, -0.02, 0)
            ))
        ]
        let tipOffsets: [Float]
        switch pose {
        case .open:
            tipOffsets = [-0.05, -0.025, 0, 0.025, 0.05]
        case .clustered:
            tipOffsets = [-0.01, -0.005, 0, 0.005, 0.01]
        }
        let tips: [HandJoint] = [
            .thumbTip,
            .indexFingerTip,
            .middleFingerTip,
            .ringFingerTip,
            .littleFingerTip
        ]
        for (joint, offset) in zip(tips, tipOffsets) {
            joints[joint] = .tracked(transform: simd_float4x4(
                translation: center + SIMD3<Float>(offset, 0, 0)
            ))
        }
        return .synthetic(hand: hand, timestamp: timestamp, joints: joints)
    }
}

@MainActor
extension RehabSessionCoordinator {
    /// Coordinator tests exercise the prepared-start state machine directly.
    /// Production launches must go through `RehabSessionLaunchSequence`.
    func startLiveForTesting(_ request: RehabSessionRequest) async {
        guard let token = prepareLiveStart(request) else { return }
        _ = await startPreparedLive(token)
    }

    func retryLiveForTesting() async {
        guard case let .failed(failure) = phase,
              failure.recoveryActions.contains(.retryLive),
              let token = prepareLiveStart(failure.request) else {
            return
        }
        _ = await startPreparedLive(token)
    }
}

@MainActor
private final class TestLiveJointSource: LiveHandJointSession {
    var isSupported = true
    var latestJointFrame: HandJointFrame?
    var viewerPosition: SIMD3<Float>?
    var tablePlacement: TablePlacement?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var startResults: [Result<Void, Error>]
    private var eventHandler: ((LiveHandJointSessionEvent, TimeInterval) -> Void)?

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

    func jointFrame(for hand: AffectedHand) -> HandJointFrame? {
        guard latestJointFrame?.hand == hand else { return nil }
        return latestJointFrame
    }

    func setEventHandler(
        _ handler: @escaping (LiveHandJointSessionEvent, TimeInterval) -> Void
    ) {
        eventHandler = handler
    }

    func emit(_ event: LiveHandJointSessionEvent, at timestamp: TimeInterval) {
        eventHandler?(event, timestamp)
    }
}

@MainActor
private final class DelayedLiveJointSource: LiveHandJointSession {
    var isSupported = true
    var latestJointFrame: HandJointFrame?
    var viewerPosition: SIMD3<Float>?
    private(set) var stopCount = 0
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var nextStartID = 0

    func start() async throws {
        let id = nextStartID
        nextStartID += 1
        try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func stop() {
        stopCount += 1
    }

    func jointFrame(for hand: AffectedHand) -> HandJointFrame? {
        guard latestJointFrame?.hand == hand else { return nil }
        return latestJointFrame
    }

    func succeedStart(_ id: Int) {
        continuations.removeValue(forKey: id)?.resume()
    }

    func waitForStartCount(_ expected: Int) async {
        while nextStartID < expected {
            await Task.yield()
        }
    }
}

private enum TestLiveError: LocalizedError {
    case denied

    var errorDescription: String? { "Tracking permission was denied" }
}
