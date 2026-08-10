import XCTest
@testable import RehabPal

final class ImmersiveRecoveryPanelTests: XCTestCase {
    // Mutation caught: showing both normal guidance and recovery guidance
    // recreates the overlapping text that blocks the hand prompt.
    func testRecoveryPresentationReplacesNormalInstructionForBriefAndLongLoss() throws {
        let request = RehabSessionRequest(experience: .exercise(.sheepDrop), prescription: .demo)
        let progress = SessionProgress(completed: 3, goal: request.goal, partial: 0)
        let brief = try XCTUnwrap(ImmersiveRecoveryPresentation.make(
            phase: .paused(request: request, progress: progress, reason: .trackingLost(requiresRecalibration: false)),
            canConfirmRecalibration: false
        ))
        XCTAssertEqual(brief.title, "Hand tracking lost")
        XCTAssertEqual(brief.progressLabel, "Completed 3 / Goal \(request.goal)")
        XCTAssertTrue(brief.replacesNormalInstruction)
        XCTAssertFalse(brief.showsRecalibrate)

        let long = try XCTUnwrap(ImmersiveRecoveryPresentation.make(
            phase: .paused(request: request, progress: progress, reason: .trackingLost(requiresRecalibration: true)),
            canConfirmRecalibration: true
        ))
        XCTAssertEqual(long.title, "Recalibration required")
        XCTAssertTrue(long.showsRecalibrate)
        XCTAssertTrue(long.canRecalibrate)
    }

    // Mutation caught: showing a disabled Recalibrate button before the
    // processor is ready invites repeated taps and contradicts the prompt.
    func testLongLossHidesRecalibrateUntilReadyThenShowsItEnabled() throws {
        let request = RehabSessionRequest(experience: .exercise(.balance), prescription: .demo)
        let phase = RehabSessionPhase.paused(
            request: request,
            progress: SessionProgress(completed: 2, goal: request.goal, partial: 0),
            reason: .trackingLost(requiresRecalibration: true)
        )
        let notReady = try XCTUnwrap(ImmersiveRecoveryPresentation.make(
            phase: phase,
            canConfirmRecalibration: false
        ))
        XCTAssertFalse(notReady.showsRecalibrate)
        XCTAssertFalse(notReady.canRecalibrate)

        let ready = try XCTUnwrap(ImmersiveRecoveryPresentation.make(
            phase: phase,
            canConfirmRecalibration: true
        ))
        XCTAssertTrue(ready.showsRecalibrate)
        XCTAssertTrue(ready.canRecalibrate)
    }

    func testRecoveryInstructionsAreExperienceSpecificAndAbsentOutsidePause() {
        let experiences: [RehabExperience] = [
            .exercise(.balance), .exercise(.squeeze), .exercise(.sheepDrop),
            .wristAssessment, .handAssessment
        ]
        let instructions = Set(experiences.compactMap { experience -> String? in
            let request = RehabSessionRequest(experience: experience, prescription: .demo)
            return ImmersiveRecoveryPresentation.make(
                phase: .paused(
                    request: request,
                    progress: SessionProgress(completed: 0, goal: request.goal, partial: 0),
                    reason: .trackingLost(requiresRecalibration: false)
                ),
                canConfirmRecalibration: false
            )?.instruction
        })
        XCTAssertEqual(instructions.count, experiences.count)
        XCTAssertNil(ImmersiveRecoveryPresentation.make(phase: .idle, canConfirmRecalibration: false))
    }
}
