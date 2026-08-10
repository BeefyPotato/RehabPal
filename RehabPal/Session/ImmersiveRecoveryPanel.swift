import SwiftUI

struct ImmersiveRecoveryPresentation: Equatable, Sendable {
    let title: String
    let progressLabel: String
    let instruction: String
    let showsRecalibrate: Bool
    let canRecalibrate: Bool
    let replacesNormalInstruction: Bool

    static func make(
        phase: RehabSessionPhase,
        canConfirmRecalibration: Bool
    ) -> Self? {
        guard case let .paused(request, progress, reason) = phase,
              case let .trackingLost(requiresRecalibration) = reason else {
            return nil
        }
        return Self(
            title: requiresRecalibration
                ? "Recalibration required"
                : "Hand tracking lost",
            progressLabel: "Completed \(progress.completed) / Goal \(progress.goal)",
            instruction: instruction(for: request.experience),
            showsRecalibrate: requiresRecalibration,
            canRecalibrate: requiresRecalibration && canConfirmRecalibration,
            replacesNormalInstruction: true
        )
    }

    private static func instruction(for experience: RehabExperience) -> String {
        switch experience {
        case .exercise(.balance):
            "Show your prescribed wrist; hold the hand level if recalibration is requested."
        case .exercise(.squeeze):
            "Show your prescribed wrist and cup your hand around the ball again."
        case .exercise(.sheepDrop):
            "Show your prescribed wrist, then bring all five fingertips around the sheep."
        case .wristAssessment:
            "Show your prescribed wrist and return to the prompted neutral pose."
        case .handAssessment:
            "Show your prescribed wrist and the joints of the prompted finger."
        }
    }
}

struct ImmersiveRecoveryPanel: View {
    let presentation: ImmersiveRecoveryPresentation
    let onRecalibrate: () -> Void
    let onBackToRoutine: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Label(presentation.title, systemImage: "hand.raised.slash.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(presentation.progressLabel)
                .font(.subheadline.monospacedDigit())
            Text(presentation.instruction)
                .font(.caption)
                .multilineTextAlignment(.center)
            HStack {
                if presentation.showsRecalibrate {
                    Button("Recalibrate", action: onRecalibrate)
                        .buttonStyle(.borderedProminent)
                        .disabled(!presentation.canRecalibrate)
                }
                Button("Back to Routine", action: onBackToRoutine)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 430)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }
}

