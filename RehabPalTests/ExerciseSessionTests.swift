import XCTest
import simd
@testable import RehabPal

@MainActor
final class ExerciseSessionTests: XCTestCase {
    // Break caught: adding a new exercise without its clinician-prescribed goal
    // can route it through the shared session with an unrelated dose.
    func testSheepDropUsesItsPrescribedExerciseContract() {
        XCTAssertEqual(ExerciseKind.sheepDrop.title, "Sheep Drop")
        XCTAssertEqual(Prescription.demo.sheepDropRepetitions, 5)
        XCTAssertEqual(
            Prescription.demo.sessionRequest(for: .exercise(.sheepDrop)).goal,
            5
        )
        XCTAssertEqual(GameplayResult.fixture(for: .sheepDrop).exercise, .sheepDrop)
    }

    // Break caught: adding Sheep Drop to the prescription without an explicit
    // shared immersive route can leave an authorized request in the empty host.
    func testSharedImmersiveRoutingSelectsEveryAuthorizedExperience() {
        let routes = [
            SharedRehabImmersiveRoute.resolve(request(for: .exercise(.balance))),
            SharedRehabImmersiveRoute.resolve(request(for: .exercise(.squeeze))),
            SharedRehabImmersiveRoute.resolve(request(for: .exercise(.sheepDrop))),
            SharedRehabImmersiveRoute.resolve(request(for: .wristAssessment)),
            SharedRehabImmersiveRoute.resolve(request(for: .handAssessment))
        ]

        XCTAssertEqual(
            routes,
            [.balance, .squeeze, .sheepDrop, .wristAssessment, .handAssessment]
        )
        XCTAssertEqual(SharedRehabImmersiveRoute.resolve(nil), .empty)
    }

    // Break caught: scene geometry or placement math can drift from the
    // processor's pen-local floor-at-zero contract.
    func testSheepDropSceneUsesReferenceGeometryAndPenLocalCoordinates() throws {
        XCTAssertEqual(SheepDropSceneConfiguration.gravity, [0, -6, 0])
        XCTAssertEqual(SheepDropSceneConfiguration.tableSize, [1, 0.015, 0.7])
        XCTAssertEqual(SheepDropSceneConfiguration.penSide, 0.36)
        XCTAssertEqual(SheepDropSceneConfiguration.fenceHeight, 0.07)
        XCTAssertEqual(SheepDropSceneConfiguration.fenceThickness, 0.012)
        XCTAssertEqual(SheepDropSceneConfiguration.spawnPadSide, 0.26)
        XCTAssertEqual(SheepDropSceneConfiguration.spawnPadGap, 0.025)
        XCTAssertEqual(SheepDropSceneConfiguration.spawnPosition.x, 0.335, accuracy: 0.000_001)
        XCTAssertEqual(SheepDropSceneConfiguration.floorY, 0)

        var placement = simd_float4x4(
            simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        )
        placement.columns.3 = SIMD4<Float>(0.4, 0.73, -0.6, 1)
        let coordinates = try XCTUnwrap(
            SheepDropCoordinateSpace(tableTransform: placement)
        )
        let expectedWorld = SIMD3<Float>(0.4, 0.785, -0.935)

        XCTAssertEqual(
            coordinates.worldPosition(fromPenLocal: [0.335, 0.055, 0]).x,
            expectedWorld.x,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            coordinates.worldPosition(fromPenLocal: [0.335, 0.055, 0]).y,
            expectedWorld.y,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            coordinates.worldPosition(fromPenLocal: [0.335, 0.055, 0]).z,
            expectedWorld.z,
            accuracy: 0.000_001
        )
        let local = coordinates.penLocalPosition(fromWorld: expectedWorld)
        XCTAssertEqual(local.x, 0.335, accuracy: 0.000_001)
        XCTAssertEqual(local.y, 0.055, accuracy: 0.000_001)
        XCTAssertEqual(local.z, 0, accuracy: 0.000_001)
        let localVelocity = coordinates.penLocalVelocity(fromWorld: [0.2, -0.1, 0])
        XCTAssertEqual(localVelocity.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(localVelocity.y, -0.1, accuracy: 0.000_001)
        XCTAssertEqual(localVelocity.z, 0.2, accuracy: 0.000_001)
    }

    // Break caught: accepting later plane updates after pickup can move the
    // physical pen while a kinematic sheep is already in the user's hand.
    func testSheepDropPlacementLocksAtFirstPickup() {
        let first = TablePlacement(
            transform: simd_float4x4(translation: [0, 0.73, -0.55]),
            source: .estimated
        )
        let later = TablePlacement(
            transform: simd_float4x4(translation: [0.2, 0.8, -0.4]),
            source: .detected
        )
        var state = SheepDropPlacementState()

        state.receive(first)
        state.lockAtFirstPickup()
        state.receive(later)
        state.receive(nil)

        XCTAssertEqual(state.placement, first)
        XCTAssertTrue(state.isLocked)
    }

    // Break caught: retaining an unlocked placement after the selector removes
    // it leaves the pen visible and interactive at an obsolete table pose.
    func testSheepDropUnlockedPlacementMirrorsRemovalAndAcceptsReplacement() {
        let detected = TablePlacement(
            transform: simd_float4x4(translation: [0, 0.73, -0.55]),
            source: .detected
        )
        let fallback = TablePlacement(
            transform: simd_float4x4(translation: [0, 0.74, -0.6]),
            source: .estimated
        )
        var state = SheepDropPlacementState()

        state.receive(detected)
        XCTAssertTrue(state.isPlacementAvailable)

        state.receive(nil)
        XCTAssertNil(state.placement)
        XCTAssertFalse(state.isPlacementAvailable)

        state.receive(fallback)
        XCTAssertEqual(state.placement, fallback)
        XCTAssertTrue(state.isPlacementAvailable)
    }

    // Break caught: a removed or changed unlocked placement can leave a
    // forming-grasp dwell alive across a period with no valid table scene.
    func testSheepDropPlacementChangeInvalidatesPartialInteraction() {
        let detected = TablePlacement(
            transform: simd_float4x4(translation: [0, 0.73, -0.55]),
            source: .detected
        )
        let replacement = TablePlacement(
            transform: simd_float4x4(translation: [0.1, 0.74, -0.5]),
            source: .estimated
        )
        var state = SheepDropPlacementState()

        XCTAssertEqual(state.receive(detected), .acquired)
        XCTAssertEqual(state.receive(nil), .invalidated)
        XCTAssertEqual(state.receive(replacement), .acquired)
        XCTAssertEqual(state.receive(replacement), .unchanged)
    }

    // Break caught: render passes can repeatedly submit one retained frame
    // with fresh render timestamps and incorrectly satisfy gesture dwell.
    func testSheepDropFrameChronologyConsumesEachObservationOnlyOnce() {
        var chronology = SheepDropInputChronology()
        let first = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 4,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )
        let newer = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 4.1,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )

        XCTAssertEqual(chronology.consume(first)?.timestamp, 4)
        XCTAssertNil(chronology.consume(first))
        XCTAssertNil(chronology.consume(HandJointFrame.synthetic(
            hand: .right,
            timestamp: 3.9,
            joints: [.wrist: .tracked(transform: matrix_identity_float4x4)]
        )))
        XCTAssertEqual(chronology.consume(newer)?.timestamp, 4.1)
    }

    // Break caught: a retained open frame can be replayed across render time
    // until the processor's release dwell completes without another sample.
    func testRepeatedRetainedFrameCannotAdvanceReleaseDwell() throws {
        let spawn = SheepDropSceneConfiguration.spawnPosition
        let source = SyntheticMovementSource(hand: .right)
        var chronology = SheepDropInputChronology()
        var session = SheepDropSession(
            affectedHand: .right,
            goal: 1,
            spawnPosition: spawn,
            sheepCollisionRadius: SheepDropSceneConfiguration.sheepCollisionRadius
        )
        let resting = SheepDropObservation(
            position: spawn,
            velocity: .zero,
            isRestingOnSpawnSurface: true,
            isOutsideSafeVolume: false
        )

        source.setSheepDropPose(.clustered, centeredAt: spawn, at: 0)
        _ = session.process(
            frame: try XCTUnwrap(chronology.consume(source.latestJointFrame)),
            observation: resting,
            at: 0
        )
        source.setSheepDropPose(.clustered, centeredAt: spawn, at: 0.25)
        _ = session.process(
            frame: try XCTUnwrap(chronology.consume(source.latestJointFrame)),
            observation: resting,
            at: 0.25
        )

        source.setSheepDropPose(.open, centeredAt: spawn, at: 0.4)
        let retainedOpen = try XCTUnwrap(chronology.consume(source.latestJointFrame))
        _ = session.process(
            frame: retainedOpen,
            observation: resting,
            at: retainedOpen.timestamp
        )
        XCTAssertNil(chronology.consume(source.latestJointFrame))
        XCTAssertEqual(session.phase, .carrying)

        source.setSheepDropPose(.open, centeredAt: spawn, at: 0.55)
        let freshOpen = try XCTUnwrap(chronology.consume(source.latestJointFrame))
        XCTAssertEqual(
            session.process(
                frame: freshOpen,
                observation: resting,
                at: freshOpen.timestamp
            ).event,
            .released
        )
    }

    // Break caught: reacquiring a table after a placement gap can count time
    // spent without a valid scene toward the original pickup dwell.
    func testPlacementGapDiscardsFormingGraspDwell() throws {
        let spawn = SheepDropSceneConfiguration.spawnPosition
        let source = SyntheticMovementSource(hand: .right)
        var session = SheepDropSession(
            affectedHand: .right,
            goal: 1,
            spawnPosition: spawn,
            sheepCollisionRadius: SheepDropSceneConfiguration.sheepCollisionRadius
        )
        let resting = SheepDropObservation(
            position: spawn,
            velocity: .zero,
            isRestingOnSpawnSurface: true,
            isOutsideSafeVolume: false
        )
        source.setSheepDropPose(.clustered, centeredAt: spawn, at: 0)
        XCTAssertEqual(
            session.process(
                frame: source.latestJointFrame,
                observation: resting,
                at: 0
            ).event,
            .formingGrasp
        )

        var placement = SheepDropPlacementState()
        _ = placement.receive(.estimatedReference)
        XCTAssertEqual(placement.receive(nil), .invalidated)
        _ = session.pause(requiresRecalibration: false)
        _ = placement.receive(.estimatedReference)

        source.setSheepDropPose(.clustered, centeredAt: spawn, at: 0.30)
        XCTAssertEqual(
            session.process(
                frame: source.latestJointFrame,
                observation: resting,
                at: 0.30
            ).event,
            .formingGrasp
        )
        XCTAssertEqual(session.progress.partial, 0)
    }

    // Break caught: independent X/Z bounds form a square and accept diagonal
    // positions farther than the approved 0.65 m horizontal radius.
    func testSheepDropSafeVolumeUsesRadialHorizontalBoundary() {
        XCTAssertFalse(SheepDropSceneConfiguration.isOutsideSafeVolume(
            [0.45, 0.2, 0.45]
        ))
        XCTAssertTrue(SheepDropSceneConfiguration.isOutsideSafeVolume(
            [0.60, 0.2, 0.60]
        ))
        XCTAssertTrue(SheepDropSceneConfiguration.isOutsideSafeVolume(
            [0, SheepDropSceneConfiguration.safeMaximumY + 0.001, 0]
        ))
    }

    // Break caught: generic phase copy can hide tracking provenance, table
    // estimation, or the explicit five-finger release instruction.
    func testSheepDropHUDUsesApprovedCopyAndDisclosure() {
        XCTAssertEqual(
            SheepDropHUDPresentation(
                phase: .findingTable,
                pauseReason: nil,
                provenance: .live,
                tableSource: nil,
                isOverPen: false
            ).instruction,
            "Finding a table…"
        )
        let live = SheepDropHUDPresentation(
            phase: .carrying,
            pauseReason: nil,
            provenance: .live,
            tableSource: .detected,
            isOverPen: true
        )
        XCTAssertEqual(live.provenanceLabel, "LIVE HAND TRACKING")
        XCTAssertEqual(live.tableLabel, "TABLE DETECTED")
        XCTAssertEqual(live.instruction, "Spread your fingers to release.")

        let demo = SheepDropHUDPresentation(
            phase: .paused,
            pauseReason: .trackingLost(requiresRecalibration: true),
            provenance: .demo,
            tableSource: .estimated,
            isOverPen: false
        )
        XCTAssertEqual(demo.provenanceLabel, "DEMO FALLBACK — SIMULATED")
        XCTAssertEqual(demo.tableLabel, "TABLE ESTIMATED")
        XCTAssertEqual(demo.instruction, "Recalibration required.")
    }

    // Break caught: forwarding a Demo action unconditionally renders an inert
    // Demo Mode button during live hand-tracking sessions.
    func testSheepDropHUDOnlyOffersDemoActionInDemoMode() {
        let actionTitle = "Open hand near spawn (Demo Mode)"
        let live = SheepDropHUDPresentation(
            phase: .waitingForHand,
            pauseReason: nil,
            provenance: .live,
            tableSource: .detected,
            isOverPen: false,
            requestedDemoActionTitle: actionTitle
        )
        let demo = SheepDropHUDPresentation(
            phase: .waitingForHand,
            pauseReason: nil,
            provenance: .demo,
            tableSource: .estimated,
            isOverPen: false,
            requestedDemoActionTitle: actionTitle
        )

        XCTAssertNil(live.demoActionTitle)
        XCTAssertEqual(demo.demoActionTitle, actionTitle)
    }

    // Break caught: a Demo button can bypass the grasp/release processor and
    // increment progress directly instead of publishing five-fingertip frames.
    func testSheepDropDemoFramesPassThroughTheRealProcessorWithoutDirectScoring() throws {
        let spawn = SheepDropSceneConfiguration.spawnPosition
        let source = SyntheticMovementSource(hand: .right)
        var session = SheepDropSession(
            affectedHand: .right,
            goal: 1,
            isSimulated: true,
            spawnPosition: spawn,
            sheepCollisionRadius: SheepDropSceneConfiguration.sheepCollisionRadius
        )
        let resting = SheepDropObservation(
            position: spawn,
            velocity: .zero,
            isRestingOnSpawnSurface: true,
            isOutsideSafeVolume: false
        )

        source.setSheepDropPose(.clustered, centeredAt: spawn, at: 0)
        XCTAssertEqual(
            session.process(frame: source.latestJointFrame, observation: resting, at: 0).event,
            .formingGrasp
        )
        source.setSheepDropPose(.clustered, centeredAt: spawn, at: 0.25)
        XCTAssertEqual(
            session.process(frame: source.latestJointFrame, observation: resting, at: 0.25).event,
            .pickupBegan
        )

        let overPen = SIMD3<Float>(0, 0.2, 0)
        source.setSheepDropPose(.clustered, centeredAt: overPen, at: 0.5)
        XCTAssertEqual(
            session.process(
                frame: source.latestJointFrame,
                observation: SheepDropObservation(
                    position: spawn,
                    velocity: .zero,
                    isRestingOnSpawnSurface: false,
                    isOutsideSafeVolume: false
                ),
                at: 0.5
            ).event,
            .carrying
        )
        source.setSheepDropPose(.open, centeredAt: overPen, at: 0.6)
        _ = session.process(
            frame: source.latestJointFrame,
            observation: SheepDropObservation(
                position: overPen,
                velocity: .zero,
                isRestingOnSpawnSurface: false,
                isOutsideSafeVolume: false
            ),
            at: 0.6
        )
        source.setSheepDropPose(.open, centeredAt: overPen, at: 0.75)
        XCTAssertEqual(
            session.process(
                frame: source.latestJointFrame,
                observation: SheepDropObservation(
                    position: overPen,
                    velocity: .zero,
                    isRestingOnSpawnSurface: false,
                    isOutsideSafeVolume: false
                ),
                at: 0.75
            ).event,
            .released
        )
        XCTAssertEqual(session.completedDrops, 0)
        XCTAssertNil(session.result)
    }

    // Break caught: hard-coding the prototype's old eight targets ignores the clinician prescription.
    func testBalanceUsesThePrescriptionTenTargetGoal() {
        let session = BalanceSession(prescription: .demo, seed: 42)

        XCTAssertEqual(Prescription.demo.balanceTargetCount, 10)
        XCTAssertEqual(session.goal, 10)
        XCTAssertEqual(session.schedule.targets.count, 10)
        XCTAssertEqual(session.progress, SessionProgress(completed: 0, goal: 10, partial: 0))
    }

    // Break caught: an unsafe or non-deterministic spawn can overlap the ball or place the hole outside the walls.
    func testBalanceTargetsAreDeterministicAndSafelySeparatedFromTheBallSpawn() {
        let schedule = BalanceTargetSchedule(seed: 42, targetCount: 10)

        XCTAssertEqual(schedule, BalanceTargetSchedule(seed: 42, targetCount: 10))
        XCTAssertTrue(schedule.targets.allSatisfy { target in
            abs(target.x) <= 0.09 &&
            abs(target.z) <= 0.09 &&
            simd_distance(target.position, SIMD2<Float>(0, -0.066)) >= 0.084
        })
    }

    // Break caught: accepting fewer than 25 unique level-hand samples makes a
    // transient pose the neutral reference instead of requiring a stable hold.
    func testBalanceCalibrationRequiresTwentyFiveUniqueConsecutiveValidFrames() {
        var session = BalanceSession(prescription: .demo, seed: 6)

        XCTAssertEqual(session.calibrationFrameGoal, 25)
        for index in 0..<24 {
            XCTAssertEqual(
                session.process(
                    frame: calibratedFrame(hand: .right, timestamp: Double(index)),
                    ballPosition: BalanceTargetSchedule.ballStart,
                    ballEscaped: false
                ),
                .waitingForCalibration
            )
            XCTAssertEqual(session.calibrationProgress, index + 1)
        }
        XCTAssertFalse(session.isCalibrated)

        let capturedWrist = MovementMath.wristTransform(pitch: 0.18, roll: -0.12, yaw: 0.3)
        guard case let .active(capturedTilt) = session.process(
            frame: calibratedFrame(hand: .right, timestamp: 24, wrist: capturedWrist),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        ) else {
            return XCTFail("Expected frame 25 to activate from its captured wrist neutral")
        }
        XCTAssertEqual(capturedTilt.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(capturedTilt.roll, 0, accuracy: 0.0001)
        XCTAssertTrue(session.isCalibrated)
        XCTAssertEqual(session.calibrationProgress, 25)
    }

    // Break caught: processing the same published tracking frame repeatedly
    // can satisfy the hold without 25 distinct hand-tracking updates.
    func testBalanceCalibrationDoesNotCountRepeatedTimestampsTwice() {
        var session = BalanceSession(prescription: .demo, seed: 6)

        _ = session.process(
            frame: calibratedFrame(hand: .right, timestamp: 0),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        )
        for _ in 0..<30 {
            XCTAssertEqual(
                session.process(
                    frame: calibratedFrame(hand: .right, timestamp: 0),
                    ballPosition: BalanceTargetSchedule.ballStart,
                    ballEscaped: false
                ),
                .waitingForCalibration
            )
        }

        XCTAssertEqual(session.calibrationProgress, 1)
        XCTAssertFalse(session.isCalibrated)
        for timestamp in 1..<24 {
            _ = session.process(
                frame: calibratedFrame(hand: .right, timestamp: Double(timestamp)),
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            )
        }
        XCTAssertEqual(session.calibrationProgress, 24)
        XCTAssertFalse(session.isCalibrated)
        _ = session.process(
            frame: calibratedFrame(hand: .right, timestamp: 24),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        )
        XCTAssertTrue(session.isCalibrated)
    }

    // Break caught: a missing frame between level-hand samples can leave the
    // old partial hold alive and calibrate from nonconsecutive observations.
    func testBalanceCalibrationMissingFrameResetsProgress() {
        var session = BalanceSession(prescription: .demo, seed: 6)
        advanceBalanceCalibration(&session, through: 9)

        XCTAssertEqual(
            session.process(frame: nil, ballPosition: .zero, ballEscaped: false),
            .waitingForCalibration
        )
        XCTAssertEqual(session.calibrationProgress, 0)
        XCTAssertFalse(session.isCalibrated)
    }

    // Break caught: an unaffected-hand sample between valid samples can leave
    // the affected hand's partial calibration hold intact.
    func testBalanceCalibrationWrongHandFrameResetsProgress() {
        var session = BalanceSession(prescription: .demo, seed: 6)
        advanceBalanceCalibration(&session, through: 9)

        XCTAssertEqual(
            session.process(
                frame: calibratedFrame(hand: .left, timestamp: 10),
                ballPosition: .zero,
                ballEscaped: false
            ),
            .waitingForCalibration
        )
        XCTAssertEqual(session.calibrationProgress, 0)
        XCTAssertFalse(session.isCalibrated)
    }

    // Break caught: an incomplete or nonlevel hand pose can be ignored without
    // breaking the stable-hold streak, allowing separated valid frames to calibrate.
    func testBalanceCalibrationInvalidPoseResetsProgress() {
        var session = BalanceSession(prescription: .demo, seed: 6)
        advanceBalanceCalibration(&session, through: 9)

        XCTAssertEqual(
            session.process(
                frame: calibratedFrame(
                    hand: .right,
                    timestamp: 10,
                    omit: .littleFingerKnuckle
                ),
                ballPosition: .zero,
                ballEscaped: false
            ),
            .waitingForCalibration
        )
        XCTAssertEqual(session.calibrationProgress, 0)
        XCTAssertFalse(session.isCalibrated)
    }

    // Break caught: accepting an older frame after a newer one lets stale data
    // extend the calibration hold and can capture an obsolete wrist transform.
    func testBalanceCalibrationRegressedTimestampResetsProgress() {
        var session = BalanceSession(prescription: .demo, seed: 6)
        advanceBalanceCalibration(&session, through: 9)

        XCTAssertEqual(
            session.process(
                frame: calibratedFrame(hand: .right, timestamp: 8),
                ballPosition: .zero,
                ballEscaped: false
            ),
            .waitingForCalibration
        )
        XCTAssertEqual(session.calibrationProgress, 0)
        XCTAssertFalse(session.isCalibrated)
    }

    // Break caught: NaN or infinite timestamps can bypass ordering checks and
    // poison chronology state while still contributing a valid-looking pose.
    func testBalanceCalibrationNonfiniteTimestampResetsProgress() {
        for timestamp in [TimeInterval.nan, .infinity, -.infinity] {
            var session = BalanceSession(prescription: .demo, seed: 6)
            advanceBalanceCalibration(&session, through: 9)

            XCTAssertEqual(
                session.process(
                    frame: calibratedFrame(hand: .right, timestamp: timestamp),
                    ballPosition: .zero,
                    ballEscaped: false
                ),
                .waitingForCalibration
            )
            XCTAssertEqual(session.calibrationProgress, 0)
            XCTAssertFalse(session.isCalibrated)
        }
    }

    // Break caught: continuing to require calibration knuckles after neutral is
    // captured makes ordinary wrist steering pause when fingers are occluded.
    func testBalanceRequiredJointsSwitchFromCalibrationPoseToWristOnly() {
        var session = BalanceSession(prescription: .demo, seed: 6)

        XCTAssertEqual(session.requiredJoints, WristNeutralCalibration.requiredJoints)
        calibrateBalance(&session)
        XCTAssertEqual(session.requiredJoints, Set([HandJoint.wrist]))
    }

    // Break caught: post-calibration knuckle occlusion can pause usable wrist
    // tracking even though only wrist orientation drives the tray.
    func testBalanceActiveTrackingIgnoresMissingKnuckles() {
        var session = BalanceSession(prescription: .demo, seed: 6)
        calibrateBalance(&session)

        XCTAssertEqual(
            session.process(
                frame: calibratedFrame(
                    hand: .right,
                    timestamp: 25,
                    omit: .littleFingerKnuckle
                ),
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            ),
            .active(WristTilt(pitch: 0, roll: 0))
        )
    }

    // Break caught: a missing wrist can leave physics active using a stale
    // transform even though the steering joint is unavailable.
    func testBalanceActiveTrackingPausesWithoutWrist() {
        var session = BalanceSession(prescription: .demo, seed: 6)
        calibrateBalance(&session)

        XCTAssertEqual(
            session.process(
                frame: calibratedFrame(hand: .right, timestamp: 26, omit: .wrist),
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            ),
            .paused
        )
    }

    // Break caught: calibration from the wrong hand or from fewer than four level knuckles can steer the prescribed exercise.
    func testBalanceCalibratesOnlyFromTheAffectedHandAndFourLevelKnuckles() {
        var session = BalanceSession(prescription: .demo, seed: 7)
        let incomplete = calibratedFrame(hand: .right, wrist: matrix_identity_float4x4, omit: .littleFingerKnuckle)

        XCTAssertEqual(session.process(frame: calibratedFrame(hand: .left), ballPosition: .zero, ballEscaped: false), .waitingForCalibration)
        XCTAssertEqual(session.process(frame: incomplete, ballPosition: .zero, ballEscaped: false), .waitingForCalibration)
        XCTAssertFalse(session.isCalibrated)

        advanceBalanceCalibration(&session, through: 23)
        let event = session.process(
            frame: calibratedFrame(hand: .right, timestamp: 24),
            ballPosition: .zero,
            ballEscaped: false
        )
        XCTAssertEqual(event, .active(WristTilt(pitch: 0, roll: 0)))
        XCTAssertTrue(session.isCalibrated)
    }

    // Break caught: proximity outside the hole or tracking loss could increment progress, while a valid drop might fail to queue a reset.
    func testBalanceScoresOnlyTrackedBallDropsAndQueuesTheNextBallReset() {
        var session = BalanceSession(prescription: .demo, seed: 9)
        let frame = calibratedFrame(hand: .right)
        calibrateBalance(&session)

        XCTAssertEqual(session.process(frame: nil, ballPosition: session.currentTarget.position, ballEscaped: false), .paused)
        XCTAssertEqual(session.completedSuccesses, 0)
        XCTAssertEqual(session.process(frame: frame, ballPosition: SIMD2<Float>(0.08, -0.066), ballEscaped: false), .resetBall(WristTilt(pitch: 0, roll: 0)))
        XCTAssertEqual(session.completedSuccesses, 0)
        XCTAssertEqual(
            session.process(frame: frame, ballPosition: BalanceTargetSchedule.ballStart, ballEscaped: false),
            .active(WristTilt(pitch: 0, roll: 0))
        )
        XCTAssertEqual(session.completedSuccesses, 0)

        let target = session.currentTarget.position
        XCTAssertEqual(
            session.process(frame: frame, ballPosition: target, ballEscaped: false),
            .scored(completed: 1, goal: 10, tilt: WristTilt(pitch: 0, roll: 0), isComplete: false)
        )
        XCTAssertEqual(session.completedSuccesses, 1)
    }

    // Break caught: an escaped physics body can silently score or remain lost instead of returning to a safe spawn.
    func testBalanceEscapeRequestsResetWithoutChangingScore() {
        var session = BalanceSession(prescription: .demo, seed: 11)
        let frame = calibratedFrame(hand: .right)
        calibrateBalance(&session)

        XCTAssertEqual(
            session.process(frame: frame, ballPosition: SIMD2<Float>(1, 1), ballEscaped: true),
            .resetBall(WristTilt(pitch: 0, roll: 0))
        )
        XCTAssertEqual(session.completedSuccesses, 0)
    }

    // Break caught: a brief interruption can discard a valid neutral or resume
    // a partially moving ball instead of preserving calibration and resetting it.
    func testBalanceBriefLossRetainsCalibrationAndResetsBallOnRecovery() {
        var session = BalanceSession(prescription: .demo, seed: 13)
        let frame = calibratedFrame(hand: .right)
        calibrateBalance(&session)

        session.pause(requiresRecalibration: false)
        XCTAssertTrue(session.isCalibrated)
        XCTAssertEqual(session.calibrationProgress, 25)
        XCTAssertEqual(session.process(frame: nil, ballPosition: .zero, ballEscaped: false), .paused)
        XCTAssertEqual(session.process(frame: frame, ballPosition: .zero, ballEscaped: false), .resetBall(WristTilt(pitch: 0, roll: 0)))
        XCTAssertTrue(session.isCalibrated)
    }

    // Break caught: a long interruption can retain an obsolete neutral, accept
    // fewer than 25 replacement frames, or erase already completed targets.
    func testBalanceLongLossRequiresNewCalibrationWithoutErasingCompletedProgress() {
        var session = BalanceSession(prescription: .demo, seed: 13)
        calibrateBalance(&session)
        XCTAssertEqual(
            session.process(
                frame: calibratedFrame(hand: .right, timestamp: 25),
                ballPosition: session.currentTarget.position,
                ballEscaped: false
            ),
            .scored(
                completed: 1,
                goal: 10,
                tilt: WristTilt(pitch: 0, roll: 0),
                isComplete: false
            )
        )

        session.pause(requiresRecalibration: true)
        XCTAssertFalse(session.isCalibrated)
        XCTAssertEqual(session.calibrationProgress, 0)
        XCTAssertEqual(session.completedSuccesses, 1)
        XCTAssertEqual(session.process(frame: nil, ballPosition: .zero, ballEscaped: false), .paused)
        for timestamp in 100..<124 {
            XCTAssertEqual(
                session.process(
                    frame: calibratedFrame(hand: .right, timestamp: Double(timestamp)),
                    ballPosition: BalanceTargetSchedule.ballStart,
                    ballEscaped: false
                ),
                .waitingForCalibration
            )
        }
        XCTAssertFalse(session.isCalibrated)
        XCTAssertEqual(session.calibrationProgress, 24)
        XCTAssertEqual(
            session.process(
                frame: calibratedFrame(hand: .right, timestamp: 124),
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            ),
            .resetBall(WristTilt(pitch: 0, roll: 0))
        )
        XCTAssertTrue(session.isCalibrated)
        XCTAssertEqual(session.completedSuccesses, 1)
    }

    // Break caught: absolute wrist rotation, yaw leakage, or a shared magnitude clamp can create unsafe tray motion.
    func testBalanceTiltIsNeutralRelativeYawFreeAndIndependentlyClamped() {
        let neutral = MovementMath.wristTransform(pitch: 0.18, roll: -0.12, yaw: 0.3)
        var session = BalanceSession(prescription: .demo, seed: 15)
        calibrateBalance(&session, wrist: neutral)

        let yawOnly = simd_mul(MovementMath.wristTransform(pitch: 0, roll: 0, yaw: 0.7), neutral)
        guard case let .active(yawTilt) = session.process(
            frame: calibratedFrame(hand: .right, wrist: yawOnly),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        ) else {
            return XCTFail("Expected active yaw-free tilt")
        }
        XCTAssertEqual(yawTilt.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(yawTilt.roll, 0, accuracy: 0.0001)

        let excessive = MovementMath.wristTransform(pitch: 0.8, roll: -0.7, yaw: 0.4)
        guard case let .active(tilt) = session.process(
            frame: calibratedFrame(hand: .right, wrist: excessive),
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        ) else {
            return XCTFail("Expected active calibrated tilt")
        }
        XCTAssertEqual(tilt.pitch, .pi / 9, accuracy: 0.0001)
        XCTAssertEqual(tilt.roll, -.pi / 9, accuracy: 0.0001)
    }

    // Break caught: completing the target count with a fixture result loses the measured prescribed/completed dose.
    func testBalanceCompletionProducesAMeasuredGameplayResult() throws {
        var session = BalanceSession(prescription: .demo, seed: 17)
        let frame = calibratedFrame(hand: .right)
        calibrateBalance(&session)

        for expected in 1...10 {
            let event = session.process(frame: frame, ballPosition: session.currentTarget.position, ballEscaped: false)
            guard case let .scored(completed, goal, _, isComplete) = event else {
                return XCTFail("Expected scored event")
            }
            XCTAssertEqual(completed, expected)
            XCTAssertEqual(goal, 10)
            XCTAssertEqual(isComplete, expected == 10)
        }

        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(result.exercise, .balance)
        XCTAssertEqual(result.prescribedDose, 10)
        XCTAssertEqual(result.completedDose, 10)
        XCTAssertTrue(result.trackingNote.contains("Measured"))
    }

    // Break caught: button-driven Demo Mode ball drops can be reported as live
    // measured physics outcomes.
    func testBalanceDemoCompletionLabelsThePayloadSimulated() throws {
        var session = BalanceSession(
            affectedHand: .right,
            goal: 1,
            seed: 17,
            isSimulated: true
        )
        let frame = calibratedFrame(hand: .right)
        calibrateBalance(&session)
        _ = session.process(frame: frame, ballPosition: session.currentTarget.position, ballEscaped: false)

        let result = try XCTUnwrap(session.result)
        XCTAssertTrue(result.trackingNote.contains("Simulated"))
        XCTAssertFalse(result.trackingNote.contains("Measured"))
    }

    func testExerciseSessionsDoNotProgressWhileTrackingIsLost() {
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

    // Break caught: the non-prescribed hand can authorize the grasp and drive a prescribed repetition.
    func testSqueezeUsesOnlyTheAffectedHandAndShowsFaceAfterStableGraspGate() {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5
        )
        let metrics = squeezeMetrics()

        XCTAssertEqual(session.process(sample: .init(hand: .left, timestamp: 0, metrics: metrics)), .waitingForGrasp)
        XCTAssertEqual(session.process(sample: .init(hand: .left, timestamp: 1, metrics: metrics)), .waitingForGrasp)
        XCTAssertNil(session.facePose)

        XCTAssertEqual(session.process(sample: .init(hand: .right, timestamp: 2, metrics: metrics)), .stabilizingGrasp)
        for step in 1..<10 {
            XCTAssertEqual(
                session.process(sample: .init(
                    hand: .right,
                    timestamp: 2 + Double(step) * 0.1,
                    metrics: metrics
                )),
                .stabilizingGrasp
            )
        }
        guard case .active = session.process(sample: .init(hand: .right, timestamp: 3, metrics: metrics)) else {
            return XCTFail("Expected accepted grasp to activate squeeze")
        }
        XCTAssertNotNil(session.facePose)
        XCTAssertEqual(session.statusLabel, "Grasp pose detected (not object verified)")
    }

    // Break caught: repeatedly adding 0.1 can leave the final Demo Mode grasp sample just short
    // of the required one-second stability duration, forcing an extra button press.
    func testSqueezeDemoGraspSamplingCrossesOneSecondInOneAction() throws {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5,
            isSimulated: true
        )
        let timestamps = SqueezeDemoSampling.graspTimestamps(startingAt: 4)

        XCTAssertEqual(timestamps.count, 11)
        XCTAssertEqual(try XCTUnwrap(timestamps.last) - XCTUnwrap(timestamps.first), 1, accuracy: 0.000_000_1)
        for timestamp in timestamps.dropLast() {
            XCTAssertEqual(
                session.process(sample: squeezeSample(at: timestamp, closure: 0)),
                .stabilizingGrasp
            )
        }
        guard case .active = session.process(
            sample: squeezeSample(at: try XCTUnwrap(timestamps.last), closure: 0)
        ) else {
            return XCTFail("Expected one demo action to accept the grasp baseline")
        }
        let facePose = try XCTUnwrap(session.facePose)
        let presentation = SqueezeHUDPresentation(
            statusLabel: session.statusLabel,
            graspDetected: true
        )

        XCTAssertNil(facePose.surfacePosition(toward: nil))
        XCTAssertEqual(
            presentation.graspDisclosure,
            "Grasp pose detected (not object verified)"
        )
        XCTAssertEqual(
            presentation.demoActionTitle,
            "Complete close–hold–reopen (Demo Mode)"
        )
        XCTAssertEqual(
            session.process(sample: squeezeSample(at: 5.1, closure: 1)),
            .active(closure: 1, phase: .closing)
        )
    }

    // Break caught: threshold crossing can skip hold/reopen phases, double-count, or continue past the exact goal.
    func testSqueezeCountsCloseHoldReopenPhasesAndStopsAtExactGoal() throws {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5
        )
        acceptSqueezeBaseline(in: &session, startingAt: 0)

        XCTAssertEqual(session.process(sample: squeezeSample(at: 1.1, closure: 1)), .active(closure: 1, phase: .closing))
        XCTAssertEqual(session.process(sample: squeezeSample(at: 1.7, closure: 1)), .active(closure: 1, phase: .held))
        XCTAssertEqual(session.process(sample: squeezeSample(at: 1.8, closure: 0.5)), .active(closure: 0.5, phase: .reopening))
        XCTAssertEqual(
            session.process(sample: squeezeSample(at: 1.9, closure: 0)),
            .repCompleted(completed: 1, goal: 1, isComplete: true)
        )
        XCTAssertEqual(session.progress, SessionProgress(completed: 1, goal: 1, partial: 0))
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.process(sample: squeezeSample(at: 2, closure: 1)), .complete)
        XCTAssertEqual(session.completedRepetitions, 1)

        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(result.exercise, .squeeze)
        XCTAssertEqual(result.prescribedDose, 1)
        XCTAssertEqual(result.completedDose, 1)
        XCTAssertTrue(result.trackingNote.contains("Measured"))
        XCTAssertTrue(result.trackingNote.contains("not object verified"))
    }

    // Break caught: losing required joints can leave the face floating or resume a half-finished repetition.
    func testSqueezeInterruptionHidesFaceDiscardsPartialRepAndPreservesCompletedReps() {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 2,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5
        )
        acceptSqueezeBaseline(in: &session, startingAt: 0)
        _ = session.process(sample: squeezeSample(at: 1.1, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.7, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.8, closure: 0.5))
        _ = session.process(sample: squeezeSample(at: 1.9, closure: 0))
        XCTAssertEqual(session.completedRepetitions, 1)

        _ = session.process(sample: squeezeSample(at: 2, closure: 1))
        XCTAssertEqual(session.process(frame: nil), .paused)
        XCTAssertNil(session.facePose)
        XCTAssertEqual(session.phase, .open)
        XCTAssertEqual(session.completedRepetitions, 1)

        XCTAssertEqual(session.process(sample: squeezeSample(at: 2.2, closure: 0)), .active(closure: 0, phase: .open))
        session.pause(requiresRecalibration: true)
        XCTAssertEqual(session.process(sample: squeezeSample(at: 4.3, closure: 0)), .stabilizingGrasp)
        XCTAssertNil(session.facePose)
        XCTAssertEqual(session.completedRepetitions, 1)
    }

    // Break caught: synthetic button-driven repetitions can claim to be measured joint-tracking outcomes.
    func testSqueezeDemoCompletionLabelsThePayloadSimulated() throws {
        var session = SqueezeSession(
            affectedHand: .right,
            goal: 1,
            closeThreshold: 0.7,
            reopenThreshold: 0.3,
            holdSeconds: 0.5,
            isSimulated: true
        )
        acceptSqueezeBaseline(in: &session, startingAt: 0)
        _ = session.process(sample: squeezeSample(at: 1.1, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.7, closure: 1))
        _ = session.process(sample: squeezeSample(at: 1.8, closure: 0.5))
        _ = session.process(sample: squeezeSample(at: 1.9, closure: 0))

        let result = try XCTUnwrap(session.result)
        XCTAssertTrue(result.trackingNote.contains("Simulated"))
        XCTAssertFalse(result.trackingNote.contains("Measured"))
    }

    private func acceptSqueezeBaseline(in session: inout SqueezeSession, startingAt timestamp: TimeInterval) {
        for step in 0..<10 {
            XCTAssertEqual(
                session.process(sample: squeezeSample(
                    at: timestamp + Double(step) * 0.1,
                    closure: 0
                )),
                .stabilizingGrasp
            )
        }
        guard case .active = session.process(sample: squeezeSample(at: timestamp + 1, closure: 0)) else {
            return XCTFail("Expected stable grasp baseline")
        }
    }

    private func squeezeSample(at timestamp: TimeInterval, closure: Float) -> SqueezeHandSample {
        .init(
            hand: .right,
            timestamp: timestamp,
            metrics: squeezeMetrics(closure: closure)
        )
    }

    private func squeezeMetrics(closure: Float = 0) -> SqueezeHandMetrics {
        SqueezeHandMetrics(
            ballCenter: SIMD3<Float>(0, 0.05, -0.45),
            radius: 0.04,
            meanTipToPalmDistance: 0.08 * (1 - 0.5 * closure),
            meanFingerFlexion: 0.3 + (.pi / 2) * closure
        )
    }

    private func calibratedFrame(
        hand: AffectedHand,
        timestamp: TimeInterval = 1,
        wrist: simd_float4x4 = matrix_identity_float4x4,
        omit omittedJoint: HandJoint? = nil
    ) -> HandJointFrame {
        let knuckles: [(HandJoint, Float)] = [
            (.indexFingerKnuckle, -0.03),
            (.middleFingerKnuckle, -0.01),
            (.ringFingerKnuckle, 0.01),
            (.littleFingerKnuckle, 0.03)
        ]
        var joints: [HandJoint: HandJointSample] = [.wrist: .tracked(transform: wrist)]
        for (joint, x) in knuckles where joint != omittedJoint {
            joints[joint] = .tracked(transform: simd_float4x4(translation: SIMD3<Float>(x, 0, 0)))
        }
        if omittedJoint == .wrist { joints[.wrist] = nil }
        return .synthetic(hand: hand, timestamp: timestamp, joints: joints)
    }

    private func advanceBalanceCalibration(
        _ session: inout BalanceSession,
        through lastTimestamp: Int,
        wrist: simd_float4x4 = matrix_identity_float4x4
    ) {
        for timestamp in 0...lastTimestamp {
            _ = session.process(
                frame: calibratedFrame(
                    hand: .right,
                    timestamp: Double(timestamp),
                    wrist: wrist
                ),
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            )
        }
    }

    private func calibrateBalance(
        _ session: inout BalanceSession,
        wrist: simd_float4x4 = matrix_identity_float4x4
    ) {
        advanceBalanceCalibration(&session, through: 24, wrist: wrist)
        XCTAssertTrue(session.isCalibrated)
    }

    private func request(for experience: RehabExperience) -> RehabSessionRequest {
        RehabSessionRequest(experience: experience, prescription: .demo)
    }
}
