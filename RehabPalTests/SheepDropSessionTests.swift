import XCTest
import simd
@testable import RehabPal

@MainActor
final class SheepDropSessionTests: XCTestCase {
    private let sheepPosition = SIMD3<Float>(0.10, 0.08, -0.05)

    // Break caught: extracting fewer than five fingertip positions, or using an
    // average separation that hides one spread finger, would accept a pinch.
    func testPoseUsesAllFiveTipsAndMaximumPairwiseSeparation() throws {
        let frame = handFrame(
            timestamp: 0,
            tips: [
                SIMD3<Float>(0.08, 0.08, -0.05),
                SIMD3<Float>(0.09, 0.08, -0.05),
                SIMD3<Float>(0.10, 0.08, -0.05),
                SIMD3<Float>(0.11, 0.08, -0.05),
                SIMD3<Float>(0.12, 0.08, -0.05)
            ]
        )

        let pose = try XCTUnwrap(FiveFingertipPose(
            frame: frame,
            sheepPosition: sheepPosition
        ))

        XCTAssertEqual(pose.tipPositions.count, 5)
        XCTAssertEqual(pose.handScale, 0.10, accuracy: 0.0001)
        XCTAssertEqual(pose.clusterRatio, 0.40, accuracy: 0.0001)
        XCTAssertEqual(pose.reachRatio, 0, accuracy: 0.0001)
        XCTAssertTrue(pose.isPickupEligible)
    }

    // Break caught: treating ring and little fingertips as optional recreates
    // the explicitly excluded thumb-index-only interaction.
    func testPoseRejectsEveryMissingRequiredFingertip() {
        for missingTip in [HandJoint.ringFingerTip, .littleFingerTip] {
            var joints = handJoints(tips: clusteredTips)
            joints[missingTip] = nil
            let frame = HandJointFrame.synthetic(hand: .right, timestamp: 0, joints: joints)

            XCTAssertNil(
                FiveFingertipPose(frame: frame, sheepPosition: sheepPosition),
                "Expected missing \(missingTip) to invalidate the pose"
            )
        }
    }

    // Break caught: counting a required but untracked/non-finite sample as
    // usable lets low-confidence tracking create a pickup candidate.
    func testPoseRejectsLowConfidenceAndNonFiniteRequiredJoints() {
        var untrackedJoints = handJoints(tips: clusteredTips)
        untrackedJoints[.middleFingerTip] = .untracked
        let untracked = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 0,
            joints: untrackedJoints
        )

        var nonFiniteJoints = handJoints(tips: clusteredTips)
        nonFiniteJoints[.indexFingerKnuckle] = tracked(SIMD3<Float>(.nan, 0, 0))
        let nonFinite = HandJointFrame.synthetic(
            hand: .right,
            timestamp: 0,
            joints: nonFiniteJoints
        )

        XCTAssertNil(FiveFingertipPose(frame: untracked, sheepPosition: sheepPosition))
        XCTAssertNil(FiveFingertipPose(frame: nonFinite, sheepPosition: sheepPosition))
    }

    // Break caught: interpreting metres as centimetres, averaging the scale,
    // or omitting the inclusive 4–14 cm plausibility gate accepts bad anatomy.
    func testPoseUsesMedianWristToKnuckleScaleAndRejectsImplausibleMetres() throws {
        let asymmetric = handFrame(
            timestamp: 0,
            knuckleDistances: [0.04, 0.08, 0.10, 0.14],
            tips: clusteredTips
        )
        let tooSmall = handFrame(
            timestamp: 0,
            knuckleDistances: [0.03, 0.03, 0.03, 0.03],
            tips: clusteredTips
        )
        let tooLarge = handFrame(
            timestamp: 0,
            knuckleDistances: [0.15, 0.15, 0.15, 0.15],
            tips: clusteredTips
        )

        let pose = try XCTUnwrap(FiveFingertipPose(
            frame: asymmetric,
            sheepPosition: sheepPosition
        ))
        XCTAssertEqual(pose.handScale, 0.09, accuracy: 0.0001)
        XCTAssertNil(FiveFingertipPose(frame: tooSmall, sheepPosition: sheepPosition))
        XCTAssertNil(FiveFingertipPose(frame: tooLarge, sheepPosition: sheepPosition))
    }

    // Break caught: checking only thumb-to-index distance would classify a
    // two-finger pinch as the required whole-hand clustered pose.
    func testThumbIndexOnlyPinchIsNotPickupEligible() throws {
        let pinch = handFrame(
            timestamp: 0,
            tips: [
                SIMD3<Float>(0.095, 0.08, -0.05),
                SIMD3<Float>(0.105, 0.08, -0.05),
                SIMD3<Float>(0.10, 0.15, -0.05),
                SIMD3<Float>(0.10, 0.08, 0.04),
                SIMD3<Float>(0.10, 0.08, -0.14)
            ]
        )

        let pose = try XCTUnwrap(FiveFingertipPose(
            frame: pinch,
            sheepPosition: sheepPosition
        ))

        XCTAssertGreaterThan(pose.clusterRatio, 0.62)
        XCTAssertFalse(pose.isPickupEligible)
    }

    // Break caught: omitting continuous dwell, or using a strict greater-than
    // boundary, picks up early or misses the prescribed 0.25-second boundary.
    func testPickupRequiresExactlyQuarterSecondOfContinuousClosePose() {
        var session = makeSession()
        let sheep = observation(position: SIMD3<Float>(0.11, 0.08, -0.05), resting: true)

        let atStart = session.process(
            frame: handFrame(timestamp: 0, tips: clusteredTips),
            observation: sheep,
            at: 0
        )
        let beforeBoundary = session.process(
            frame: handFrame(timestamp: 0.24, tips: clusteredTips),
            observation: sheep,
            at: 0.24
        )

        XCTAssertEqual(atStart.event, .formingGrasp)
        XCTAssertEqual(beforeBoundary.event, .formingGrasp)
        XCTAssertEqual(session.phase, .formingGrasp)
        XCTAssertEqual(session.progress.partial, 0.96, accuracy: 0.0001)

        let atBoundary = session.process(
            frame: handFrame(timestamp: 0.25, tips: clusteredTips),
            observation: sheep,
            at: 0.25
        )

        XCTAssertEqual(atBoundary.event, .pickupBegan)
        XCTAssertEqual(
            atBoundary.command,
            .pickup(position: SIMD3<Float>(0.11, 0.08, -0.05))
        )
        XCTAssertEqual(session.phase, .carrying)
        XCTAssertEqual(session.progress.partial, 0)
    }

    // Break caught: accepting the frame chirality without comparing it to the
    // prescribed hand allows the unaffected hand to pick up the sheep.
    func testWrongHandCannotAccumulatePickupDwell() {
        var session = makeSession(affectedHand: .left)
        let sheep = observation(position: sheepPosition, resting: true)

        _ = session.process(
            frame: handFrame(hand: .right, timestamp: 0, tips: clusteredTips),
            observation: sheep,
            at: 0
        )
        let update = session.process(
            frame: handFrame(hand: .right, timestamp: 0.25, tips: clusteredTips),
            observation: sheep,
            at: 0.25
        )

        XCTAssertEqual(update.event, .waitingForHand)
        XCTAssertEqual(update.command, .none)
        XCTAssertEqual(session.phase, .waitingForHand)
        XCTAssertEqual(session.progress.partial, 0)
    }

    // Break caught: retaining dwell across an unusable frame permits two
    // discontinuous snippets to satisfy a continuous hold.
    func testInvalidPoseResetsPickupDwellStart() {
        var session = makeSession()
        let sheep = observation(position: sheepPosition, resting: true)

        _ = session.process(
            frame: handFrame(timestamp: 0, tips: clusteredTips),
            observation: sheep,
            at: 0
        )
        _ = session.process(frame: nil, observation: sheep, at: 0.20)
        _ = session.process(
            frame: handFrame(timestamp: 0.25, tips: clusteredTips),
            observation: sheep,
            at: 0.25
        )
        let stillWaiting = session.process(
            frame: handFrame(timestamp: 0.49, tips: clusteredTips),
            observation: sheep,
            at: 0.49
        )
        let pickup = session.process(
            frame: handFrame(timestamp: 0.50, tips: clusteredTips),
            observation: sheep,
            at: 0.50
        )

        XCTAssertEqual(stillWaiting.event, .formingGrasp)
        XCTAssertEqual(pickup.event, .pickupBegan)
    }

    // Break caught: subtracting timestamps without enforcing monotonic input
    // can turn a clock regression into retained or negative dwell state.
    func testBackwardTimestampCannotContributeToPickupDwell() {
        var session = makeSession()
        let sheep = observation(position: sheepPosition, resting: true)

        _ = session.process(
            frame: handFrame(timestamp: 1, tips: clusteredTips),
            observation: sheep,
            at: 1
        )
        let regressed = session.process(
            frame: handFrame(timestamp: 0.5, tips: clusteredTips),
            observation: sheep,
            at: 0.5
        )
        let restarted = session.process(
            frame: handFrame(timestamp: 1.25, tips: clusteredTips),
            observation: sheep,
            at: 1.25
        )
        let pickup = session.process(
            frame: handFrame(timestamp: 1.50, tips: clusteredTips),
            observation: sheep,
            at: 1.50
        )

        XCTAssertEqual(regressed.event, .waitingForHand)
        XCTAssertEqual(restarted.event, .formingGrasp)
        XCTAssertEqual(pickup.event, .pickupBegan)
    }

    // Break caught: recapturing the offset or commanding the raw centroid
    // makes the sheep snap into the hand instead of following from its pickup
    // displacement; using a linear blend breaks the 0.08-second time constant.
    func testCarryPreservesCapturedOffsetAndExponentiallySmoothsCentroid() throws {
        var session = makeSession()
        let pickupSheep = observation(
            position: SIMD3<Float>(0.11, 0.08, -0.05),
            resting: true
        )
        beginCarry(session: &session, sheep: pickupSheep)
        let shiftedTips = clusteredTips.map { $0 + SIMD3<Float>(0.10, 0, 0) }

        let update = session.process(
            frame: handFrame(timestamp: 0.33, tips: shiftedTips),
            observation: observation(position: SIMD3<Float>(0.11, 0.08, -0.05)),
            at: 0.33
        )
        guard case let .carry(position) = update.command else {
            return XCTFail("Expected a carry command, got \(update.command)")
        }

        XCTAssertEqual(update.event, .carrying)
        XCTAssertEqual(position.x, 0.173212, accuracy: 0.0001)
        XCTAssertEqual(position.y, 0.08, accuracy: 0.0001)
        XCTAssertEqual(position.z, -0.05, accuracy: 0.0001)
    }

    // Break caught: using the pickup threshold for release removes hysteresis
    // and releases while the five fingertips remain in the 0.62–0.95 band.
    func testCarryStaysLatchedInsideClusterHysteresisBand() {
        var session = makeSession()
        let sheep = observation(position: sheepPosition, resting: true)
        beginCarry(session: &session, sheep: sheep)
        let hysteresisTips = tips(center: sheepPosition, maximumSeparation: 0.08)

        let update = session.process(
            frame: handFrame(timestamp: 0.40, tips: hysteresisTips),
            observation: observation(position: sheepPosition),
            at: 0.40
        )

        XCTAssertEqual(update.event, .carrying)
        XCTAssertNotEqual(update.command, .release)
        XCTAssertEqual(session.phase, .carrying)
    }

    // Break caught: releasing on the first open frame or using the wrong
    // comparison emits release before the continuous 0.15-second boundary.
    func testReleaseRequiresExactlyFifteenHundredthsOfOpenPose() {
        var session = makeSession()
        let sheep = observation(position: sheepPosition, resting: true)
        beginCarry(session: &session, sheep: sheep)
        let openTips = tips(center: sheepPosition, maximumSeparation: 0.10)

        let opened = session.process(
            frame: handFrame(timestamp: 0.30, tips: openTips),
            observation: observation(position: sheepPosition),
            at: 0.30
        )
        let beforeBoundary = session.process(
            frame: handFrame(timestamp: 0.44, tips: openTips),
            observation: observation(position: sheepPosition),
            at: 0.44
        )
        let atBoundary = session.process(
            frame: handFrame(timestamp: 0.45, tips: openTips),
            observation: observation(position: sheepPosition),
            at: 0.45
        )

        XCTAssertEqual(opened.event, .carrying)
        XCTAssertEqual(beforeBoundary.event, .carrying)
        XCTAssertNotEqual(beforeBoundary.command, .release)
        XCTAssertEqual(atBoundary.event, .released)
        XCTAssertEqual(atBoundary.command, .release)
        XCTAssertEqual(session.phase, .falling)
    }

    // Break caught: interpreting absent fingertips as an open pose releases a
    // sheep during tracking loss instead of freezing the last physical state.
    func testMissingTrackingDuringCarryFreezesAndNeverReleases() {
        var session = makeSession()
        let sheep = observation(position: sheepPosition, resting: true)
        beginCarry(session: &session, sheep: sheep)

        let update = session.process(
            frame: nil,
            observation: observation(position: SIMD3<Float>(0.14, 0.12, -0.03)),
            at: 0.40
        )

        XCTAssertEqual(update.event, .trackingPaused(requiresRecalibration: false))
        XCTAssertEqual(
            update.command,
            .freeze(position: SIMD3<Float>(0.14, 0.12, -0.03))
        )
        XCTAssertNotEqual(update.command, .release)
        XCTAssertEqual(session.phase, .paused)
    }

    // Break caught: axis-wise clamping permits a diagonal reach beyond 65 cm,
    // while omitting vertical clamps can drive the sheep through the table or
    // above the 45 cm carry ceiling.
    func testCarryCommandIsClampedToRadialAndVerticalSafeVolume() {
        var upperSession = makeSession()
        let sheep = observation(position: sheepPosition, resting: true)
        beginCarry(session: &upperSession, sheep: sheep)
        let farHighTips = clusteredTips.map { $0 + SIMD3<Float>(1, 1, 1) }

        let upper = upperSession.process(
            frame: handFrame(timestamp: 10, tips: farHighTips),
            observation: observation(position: sheepPosition),
            at: 10
        )
        guard case let .carry(upperPosition) = upper.command else {
            return XCTFail("Expected upper carry command")
        }
        XCTAssertEqual(
            simd_length(SIMD2<Float>(upperPosition.x, upperPosition.z)),
            0.65,
            accuracy: 0.0001
        )
        XCTAssertEqual(upperPosition.y, 0.45, accuracy: 0.0001)

        var lowerSession = makeSession()
        beginCarry(session: &lowerSession, sheep: sheep)
        let lowTips = clusteredTips.map { $0 + SIMD3<Float>(0, -1, 0) }
        let lower = lowerSession.process(
            frame: handFrame(timestamp: 10, tips: lowTips),
            observation: observation(position: sheepPosition),
            at: 10
        )
        guard case let .carry(lowerPosition) = lower.command else {
            return XCTFail("Expected lower carry command")
        }
        XCTAssertEqual(lowerPosition.y, 0.03, accuracy: 0.0001)
    }

    // Break caught: scoring from sheep physics alone allows a sheep already in
    // the pen, or moved there by some other cause, to score without release.
    func testSettledSheepCannotScoreBeforeExplicitOpenHandRelease() {
        var session = makeSession()
        let settledInPen = observation(position: SIMD3<Float>(0, 0.03, 0))
        let openTips = tips(center: .zero, maximumSeparation: 0.10)

        _ = session.process(
            frame: handFrame(timestamp: 0, tips: openTips),
            observation: settledInPen,
            at: 0
        )
        let update = session.process(
            frame: handFrame(timestamp: 0.25, tips: openTips),
            observation: settledInPen,
            at: 0.25
        )

        XCTAssertEqual(update.event, .waitingForHand)
        XCTAssertEqual(session.completedDrops, 0)
        XCTAssertNil(session.result)
    }

    // Break caught: including the fence footprint instead of the inner pen
    // boundary scores sheep whose center remains outside the usable interior.
    func testReleasedSheepOutsideInnerPenBoundsDoesNotScore() {
        var session = releasedSession()
        let outside = observation(position: SIMD3<Float>(0.169, 0.03, 0))

        let update = session.process(frame: nil, observation: outside, at: 0.50)

        XCTAssertEqual(update.event, .failedDropReset)
        XCTAssertEqual(session.completedDrops, 0)
    }

    // Break caught: comparing height to a fixed world value instead of 2.5
    // collision radii scores an airborne sheep.
    func testReleasedSheepAboveTwoAndAHalfRadiiDoesNotScore() {
        var session = releasedSession()
        let airborne = observation(position: SIMD3<Float>(0, 0.076, 0))

        _ = session.process(frame: nil, observation: airborne, at: 0.50)
        let update = session.process(frame: nil, observation: airborne, at: 0.75)

        XCTAssertEqual(update.event, .falling)
        XCTAssertEqual(session.completedDrops, 0)
    }

    // Break caught: checking a single velocity axis, or using centimetres per
    // second, scores a sheep moving faster than 0.08 m/s.
    func testReleasedSheepAboveEightCentimetresPerSecondDoesNotScore() {
        var session = releasedSession()
        let moving = observation(
            position: SIMD3<Float>(0, 0.03, 0),
            velocity: SIMD3<Float>(0.0573, 0.0573, 0)
        )

        _ = session.process(frame: nil, observation: moving, at: 0.50)
        let update = session.process(frame: nil, observation: moving, at: 0.75)

        XCTAssertEqual(update.event, .falling)
        XCTAssertEqual(session.completedDrops, 0)
    }

    // Break caught: scoring on entry, at 0.24 seconds, or only after greater
    // than 0.25 seconds violates the settled dwell boundary.
    func testReleasedSheepScoresAtExactlyQuarterSecondSettled() {
        var session = releasedSession()
        let settled = observation(position: SIMD3<Float>(0, 0.03, 0))

        let atStart = session.process(frame: nil, observation: settled, at: 0.50)
        let beforeBoundary = session.process(frame: nil, observation: settled, at: 0.74)
        let atBoundary = session.process(frame: nil, observation: settled, at: 0.75)

        XCTAssertEqual(atStart.event, .falling)
        XCTAssertEqual(beforeBoundary.event, .falling)
        XCTAssertEqual(session.completedDrops, 1)
        XCTAssertEqual(
            atBoundary.event,
            .placementSucceeded(completed: 1, goal: 5, deadline: 1.55)
        )
        XCTAssertEqual(atBoundary.command, .none)
        XCTAssertEqual(session.phase, .success)
        XCTAssertEqual(session.progress, SessionProgress(completed: 1, goal: 5, partial: 0))
    }

    // Break caught: leaving the processor in falling after success allows
    // duplicate settled frames for the same sheep to increment more than once.
    func testDuplicateFramesAfterSuccessCannotScoreSameSheepTwice() {
        var session = releasedSession()
        let settled = observation(position: SIMD3<Float>(0, 0.03, 0))
        _ = session.process(frame: nil, observation: settled, at: 0.50)
        _ = session.process(frame: nil, observation: settled, at: 0.75)

        let duplicate = session.process(frame: nil, observation: settled, at: 1.00)

        XCTAssertEqual(duplicate.event, .successWaiting(deadline: 1.55))
        XCTAssertEqual(duplicate.command, .none)
        XCTAssertEqual(session.completedDrops, 1)
    }

    // Break caught: respawning immediately hides the 0.8-second success state,
    // while an unowned view timer makes reset timing nondeterministic.
    func testSuccessfulPlacementOwnsEightTenthsSecondResetDeadline() {
        var session = releasedSession()
        let settled = observation(position: SIMD3<Float>(0, 0.03, 0))
        _ = session.process(frame: nil, observation: settled, at: 0.50)
        _ = session.process(frame: nil, observation: settled, at: 0.75)

        let beforeDeadline = session.process(frame: nil, observation: settled, at: 1.549)
        let atDeadline = session.process(frame: nil, observation: settled, at: 1.55)

        XCTAssertEqual(beforeDeadline.event, .successWaiting(deadline: 1.55))
        XCTAssertEqual(atDeadline.event, .resetAfterSuccess)
        XCTAssertEqual(
            atDeadline.command,
            .reset(
                position: SIMD3<Float>(0.25, 0.03, 0),
                linearVelocity: .zero,
                angularVelocity: .zero
            )
        )
        XCTAssertEqual(session.phase, .resetting)
    }

    // Break caught: omitting the one-second ceiling leaves an unsuccessful
    // physical drop falling indefinitely instead of respawning.
    func testFailedReleaseResetsAtOneSecondWithZeroVelocities() {
        var session = releasedSession()
        let outsidePen = observation(position: SIMD3<Float>(0.25, 0.20, 0))

        let beforeDeadline = session.process(
            frame: nil,
            observation: outsidePen,
            at: 1.449
        )
        let atDeadline = session.process(
            frame: nil,
            observation: outsidePen,
            at: 1.45
        )

        XCTAssertEqual(beforeDeadline.event, .falling)
        XCTAssertEqual(atDeadline.event, .failedDropReset)
        XCTAssertEqual(
            atDeadline.command,
            .reset(
                position: SIMD3<Float>(0.25, 0.03, 0),
                linearVelocity: .zero,
                angularVelocity: .zero
            )
        )
        XCTAssertEqual(session.completedDrops, 0)
    }

    // Break caught: waiting for the observation timeout after an escape can
    // leave a lost sheep active outside the safe play volume.
    func testOutsideSafeVolumeResetsFailedReleaseImmediately() {
        var session = releasedSession()
        let escaped = observation(
            position: SIMD3<Float>(0.80, -0.20, 0),
            outsideSafeVolume: true
        )

        let update = session.process(frame: nil, observation: escaped, at: 0.46)

        XCTAssertEqual(update.event, .failedDropReset)
        XCTAssertEqual(
            update.command,
            .reset(
                position: SIMD3<Float>(0.25, 0.03, 0),
                linearVelocity: .zero,
                angularVelocity: .zero
            )
        )
    }

    // Break caught: a tracking-loss reset that reconstructs progress from the
    // active attempt can erase already completed placements.
    func testPauseClearsPartialAttemptButPreservesCompletedPlacements() {
        var session = makeSession(goal: 2)
        scoreOneDrop(session: &session, baseTime: 0)
        _ = session.process(
            frame: nil,
            observation: observation(position: .zero),
            at: 1.55
        )
        _ = session.process(
            frame: nil,
            observation: observation(position: .zero),
            at: 1.56
        )
        let secondSheep = observation(position: sheepPosition, resting: true)
        beginCarry(session: &session, sheep: secondSheep, baseTime: 2)

        let update = session.pause(requiresRecalibration: true)

        XCTAssertEqual(update.event, .trackingPaused(requiresRecalibration: true))
        XCTAssertEqual(
            update.command,
            .reset(
                position: SIMD3<Float>(0.25, 0.03, 0),
                linearVelocity: .zero,
                angularVelocity: .zero
            )
        )
        XCTAssertEqual(session.progress, SessionProgress(completed: 1, goal: 2, partial: 0))
        XCTAssertNil(session.result)
    }

    // Break caught: retaining settled dwell across a tracking pause lets time
    // before missing tracking contribute to the continuous scoring interval.
    func testTrackingPauseDiscardsPartialSettledDwell() {
        var session = releasedSession()
        let settled = observation(position: SIMD3<Float>(0, 0.03, 0))
        _ = session.process(frame: nil, observation: settled, at: 0.50)

        let pause = session.pause(requiresRecalibration: false)
        let resumed = session.process(frame: nil, observation: settled, at: 0.75)
        let beforeNewBoundary = session.process(frame: nil, observation: settled, at: 0.99)
        let atNewBoundary = session.process(frame: nil, observation: settled, at: 1.00)

        XCTAssertEqual(pause.event, .trackingPaused(requiresRecalibration: false))
        XCTAssertEqual(resumed.event, .falling)
        XCTAssertEqual(beforeNewBoundary.event, .falling)
        XCTAssertEqual(
            atNewBoundary.event,
            .placementSucceeded(completed: 1, goal: 5, deadline: 1.80)
        )
    }

    // Break caught: routing a non-finite or regressed timestamp through the
    // pickup waiting path abandons the explicit release and prevents scoring.
    func testInvalidOrRegressedTimestampPreservesFallingAndExplicitRelease() {
        for (label, invalidTimestamp) in [("non-finite", .nan), ("regressed", 0.40)] {
            var session = releasedSession()
            let settled = observation(position: SIMD3<Float>(0, 0.03, 0))
            _ = session.process(frame: nil, observation: settled, at: 0.50)

            let rejected = session.process(
                frame: nil,
                observation: settled,
                at: invalidTimestamp
            )

            XCTAssertEqual(rejected.event, .falling, label)
            XCTAssertEqual(
                rejected.command,
                .freeze(position: SIMD3<Float>(0, 0.03, 0)),
                label
            )
            XCTAssertEqual(session.phase, .falling, label)
            XCTAssertEqual(session.completedDrops, 0, label)

            let restarted = session.process(frame: nil, observation: settled, at: 0.75)
            let beforeBoundary = session.process(frame: nil, observation: settled, at: 0.99)
            let atBoundary = session.process(frame: nil, observation: settled, at: 1.00)

            XCTAssertEqual(restarted.event, .falling, label)
            XCTAssertEqual(beforeBoundary.event, .falling, label)
            XCTAssertEqual(
                atBoundary.event,
                .placementSucceeded(completed: 1, goal: 5, deadline: 1.80),
                label
            )
        }
    }

    // Break caught: sending bad time through waiting while success owns its
    // deadline can preserve the integer count but make the final result unreachable.
    func testInvalidOrRegressedTimestampPreservesSuccessDeadlineAndResult() throws {
        for (label, invalidTimestamp) in [("non-finite", .nan), ("regressed", 0.70)] {
            var session = makeSession(goal: 1)
            scoreOneDrop(session: &session, baseTime: 0)

            let rejected = session.process(
                frame: nil,
                observation: observation(position: .zero),
                at: invalidTimestamp
            )

            XCTAssertEqual(rejected.event, .successWaiting(deadline: 1.55), label)
            XCTAssertEqual(rejected.command, .none, label)
            XCTAssertEqual(session.phase, .success, label)
            XCTAssertEqual(session.completedDrops, 1, label)

            let completion = session.process(
                frame: nil,
                observation: observation(position: .zero),
                at: 1.55
            )
            let result = try XCTUnwrap(session.result, label)
            XCTAssertEqual(completion.event, .complete(result), label)
        }
    }

    // Break caught: a global bad-time fallback can move an already complete
    // processor back to waiting and break terminal idempotence.
    func testInvalidOrRegressedTimestampKeepsCompletionTerminal() throws {
        for (label, invalidTimestamp) in [("non-finite", .nan), ("regressed", 0.70)] {
            var session = completedOneDropSession()
            let result = try XCTUnwrap(session.result, label)

            let rejected = session.process(
                frame: nil,
                observation: observation(position: .zero),
                at: invalidTimestamp
            )

            XCTAssertEqual(rejected.event, .complete(result), label)
            XCTAssertEqual(rejected.command, .none, label)
            XCTAssertEqual(session.phase, .complete, label)
            XCTAssertEqual(session.result, result, label)
        }
    }

    // Break caught: restoring only carrying/falling after pause loses the
    // final success deadline; recalibration must not erase the earned result path.
    func testPauseDuringFinalSuccessPreservesResultForBothPauseModes() throws {
        for requiresRecalibration in [false, true] {
            var session = makeSession(goal: 1)
            scoreOneDrop(session: &session, baseTime: 0)

            let pause = session.pause(requiresRecalibration: requiresRecalibration)

            XCTAssertEqual(
                pause.event,
                .trackingPaused(requiresRecalibration: requiresRecalibration)
            )
            XCTAssertEqual(session.progress, SessionProgress(completed: 1, goal: 1, partial: 0))

            let completion = session.process(
                frame: nil,
                observation: observation(position: .zero),
                at: 1.55
            )
            let result = try XCTUnwrap(session.result)
            XCTAssertEqual(completion.event, .complete(result))
            XCTAssertEqual(session.phase, .complete)
        }
    }

    // Break caught: losing nonfinal success across pause prevents the owned
    // deadline from emitting the reset command for the next sheep.
    func testPauseDuringNonfinalSuccessPreservesResetForBothPauseModes() {
        for requiresRecalibration in [false, true] {
            var session = makeSession(goal: 2)
            scoreOneDrop(session: &session, baseTime: 0)

            _ = session.pause(requiresRecalibration: requiresRecalibration)
            let reset = session.process(
                frame: nil,
                observation: observation(position: .zero),
                at: 1.55
            )

            XCTAssertEqual(reset.event, .resetAfterSuccess)
            XCTAssertEqual(
                reset.command,
                .reset(
                    position: SIMD3<Float>(0.25, 0.03, 0),
                    linearVelocity: .zero,
                    angularVelocity: .zero
                )
            )
            XCTAssertEqual(session.phase, .resetting)
            XCTAssertEqual(session.progress, SessionProgress(completed: 1, goal: 2, partial: 0))
        }
    }

    // Break caught: applying pause generically after completion can overwrite
    // the terminal phase and immutable result for either recovery mode.
    func testPauseAfterCompletionKeepsTerminalResultForBothPauseModes() throws {
        for requiresRecalibration in [false, true] {
            var session = completedOneDropSession()
            let result = try XCTUnwrap(session.result)

            let pause = session.pause(requiresRecalibration: requiresRecalibration)
            let duplicate = session.process(
                frame: nil,
                observation: observation(position: .zero),
                at: 2
            )

            XCTAssertEqual(pause.event, .complete(result))
            XCTAssertEqual(pause.command, .none)
            XCTAssertEqual(duplicate.event, .complete(result))
            XCTAssertEqual(session.phase, .complete)
            XCTAssertEqual(session.result, result)
        }
    }

    // Break caught: finishing at an assumed default or incrementing on reset
    // produces a result whose prescribed/completed dose is not exactly five.
    func testFiveSuccessfulDropsCreateSheepDropGameplayResult() throws {
        var session = makeSession(goal: 5)
        var completion: SheepDropUpdate?

        for drop in 0..<5 {
            let base = TimeInterval(drop) * 2
            scoreOneDrop(session: &session, baseTime: base)
            let deadline = base + 1.55
            let update = session.process(
                frame: nil,
                observation: observation(position: .zero),
                at: deadline
            )
            if drop < 4 {
                XCTAssertEqual(update.event, .resetAfterSuccess)
                _ = session.process(
                    frame: nil,
                    observation: observation(position: .zero),
                    at: deadline + 0.01
                )
            } else {
                completion = update
            }
        }

        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(completion?.event, .complete(result))
        XCTAssertEqual(session.phase, .complete)
        XCTAssertEqual(result.exercise, .sheepDrop)
        XCTAssertEqual(result.prescribedDose, 5)
        XCTAssertEqual(result.completedDose, 5)
        XCTAssertTrue(result.trackingNote.contains("five-fingertip joint observations"))
    }

    // Break caught: reusing the live tracking note for Demo Mode conceals that
    // its joint observations were simulated.
    func testDemoCompletionNamesSimulatedJointObservations() throws {
        var session = makeSession(goal: 1, isSimulated: true)
        scoreOneDrop(session: &session, baseTime: 0)
        let completion = session.process(
            frame: nil,
            observation: observation(position: .zero),
            at: 1.55
        )

        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(completion.event, .complete(result))
        XCTAssertTrue(result.trackingNote.contains("Simulated joint observations"))

        let duplicate = session.process(
            frame: nil,
            observation: observation(position: .zero),
            at: 2
        )
        XCTAssertEqual(duplicate.event, .complete(result))
        XCTAssertEqual(session.completedDrops, 1)
    }

    private var clusteredTips: [SIMD3<Float>] {
        [
            SIMD3<Float>(0.08, 0.08, -0.05),
            SIMD3<Float>(0.09, 0.08, -0.05),
            SIMD3<Float>(0.10, 0.08, -0.05),
            SIMD3<Float>(0.11, 0.08, -0.05),
            SIMD3<Float>(0.12, 0.08, -0.05)
        ]
    }

    private func handFrame(
        hand: AffectedHand = .right,
        timestamp: TimeInterval,
        knuckleDistances: [Float] = [0.10, 0.10, 0.10, 0.10],
        tips: [SIMD3<Float>]
    ) -> HandJointFrame {
        HandJointFrame.synthetic(
            hand: hand,
            timestamp: timestamp,
            joints: handJoints(knuckleDistances: knuckleDistances, tips: tips)
        )
    }

    private func handJoints(
        knuckleDistances: [Float] = [0.10, 0.10, 0.10, 0.10],
        tips: [SIMD3<Float>]
    ) -> [HandJoint: HandJointSample] {
        precondition(knuckleDistances.count == 4)
        precondition(tips.count == 5)
        return [
            .wrist: tracked(.zero),
            .indexFingerKnuckle: tracked(SIMD3<Float>(knuckleDistances[0], 0, 0)),
            .middleFingerKnuckle: tracked(SIMD3<Float>(0, knuckleDistances[1], 0)),
            .ringFingerKnuckle: tracked(SIMD3<Float>(-knuckleDistances[2], 0, 0)),
            .littleFingerKnuckle: tracked(SIMD3<Float>(0, -knuckleDistances[3], 0)),
            .thumbTip: tracked(tips[0]),
            .indexFingerTip: tracked(tips[1]),
            .middleFingerTip: tracked(tips[2]),
            .ringFingerTip: tracked(tips[3]),
            .littleFingerTip: tracked(tips[4])
        ]
    }

    private func tracked(_ position: SIMD3<Float>) -> HandJointSample {
        .tracked(transform: simd_float4x4(translation: position))
    }

    private func makeSession(
        affectedHand: AffectedHand = .right,
        goal: Int = 5,
        isSimulated: Bool = false
    ) -> SheepDropSession {
        SheepDropSession(
            affectedHand: affectedHand,
            goal: goal,
            isSimulated: isSimulated,
            spawnPosition: SIMD3<Float>(0.25, 0.03, 0),
            sheepCollisionRadius: 0.03
        )
    }

    private func observation(
        position: SIMD3<Float>,
        velocity: SIMD3<Float> = .zero,
        resting: Bool = false,
        outsideSafeVolume: Bool = false
    ) -> SheepDropObservation {
        SheepDropObservation(
            position: position,
            velocity: velocity,
            isRestingOnSpawnSurface: resting,
            isOutsideSafeVolume: outsideSafeVolume
        )
    }

    private func beginCarry(
        session: inout SheepDropSession,
        sheep: SheepDropObservation,
        baseTime: TimeInterval = 0
    ) {
        _ = session.process(
            frame: handFrame(timestamp: baseTime, tips: clusteredTips),
            observation: sheep,
            at: baseTime
        )
        let pickup = session.process(
            frame: handFrame(timestamp: baseTime + 0.25, tips: clusteredTips),
            observation: sheep,
            at: baseTime + 0.25
        )
        XCTAssertEqual(pickup.event, .pickupBegan)
    }

    private func releasedSession(
        goal: Int = 5,
        isSimulated: Bool = false
    ) -> SheepDropSession {
        var session = makeSession(goal: goal, isSimulated: isSimulated)
        let sheep = observation(position: sheepPosition, resting: true)
        beginCarry(session: &session, sheep: sheep)
        let openTips = tips(center: sheepPosition, maximumSeparation: 0.10)
        _ = session.process(
            frame: handFrame(timestamp: 0.30, tips: openTips),
            observation: observation(position: sheepPosition),
            at: 0.30
        )
        let release = session.process(
            frame: handFrame(timestamp: 0.45, tips: openTips),
            observation: observation(position: sheepPosition),
            at: 0.45
        )
        XCTAssertEqual(release.event, .released)
        return session
    }

    private func scoreOneDrop(
        session: inout SheepDropSession,
        baseTime: TimeInterval
    ) {
        let sheep = observation(position: sheepPosition, resting: true)
        beginCarry(session: &session, sheep: sheep, baseTime: baseTime)
        let openTips = tips(center: sheepPosition, maximumSeparation: 0.10)
        _ = session.process(
            frame: handFrame(timestamp: baseTime + 0.30, tips: openTips),
            observation: observation(position: sheepPosition),
            at: baseTime + 0.30
        )
        let release = session.process(
            frame: handFrame(timestamp: baseTime + 0.45, tips: openTips),
            observation: observation(position: sheepPosition),
            at: baseTime + 0.45
        )
        XCTAssertEqual(release.event, .released)

        let settled = observation(position: SIMD3<Float>(0, 0.03, 0))
        _ = session.process(frame: nil, observation: settled, at: baseTime + 0.50)
        let success = session.process(
            frame: nil,
            observation: settled,
            at: baseTime + 0.75
        )
        XCTAssertEqual(session.phase, .success)
        XCTAssertEqual(success.command, .none)
    }

    private func completedOneDropSession() -> SheepDropSession {
        var session = makeSession(goal: 1)
        scoreOneDrop(session: &session, baseTime: 0)
        let completion = session.process(
            frame: nil,
            observation: observation(position: .zero),
            at: 1.55
        )
        XCTAssertEqual(session.phase, .complete)
        XCTAssertNotNil(session.result)
        if let result = session.result {
            XCTAssertEqual(completion.event, .complete(result))
        }
        return session
    }

    private func tips(
        center: SIMD3<Float>,
        maximumSeparation: Float
    ) -> [SIMD3<Float>] {
        let half = maximumSeparation / 2
        return [
            center + SIMD3<Float>(-half, 0, 0),
            center + SIMD3<Float>(-half / 2, 0, 0),
            center,
            center + SIMD3<Float>(half / 2, 0, 0),
            center + SIMD3<Float>(half, 0, 0)
        ]
    }
}
