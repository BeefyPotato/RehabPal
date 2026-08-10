import SwiftUI

/// Shared prescribed-dose count used by every rep-based immersive experience.
struct SessionProgressLabel: View {
    let progress: SessionProgress

    var body: some View {
        Text("Completed \(progress.completed) / Goal \(progress.goal)")
            .font(.title2.bold())
            .accessibilityLabel("Completed \(progress.completed), goal \(progress.goal)")
    }
}

struct DiagnosticHUDPresentation: Equatable, Sendable {
    let progress: SessionProgress
    let subject: String
    let phase: String
    let isDemo: Bool

    var attemptLabel: String {
        let attempt = min(progress.completed + 1, progress.goal)
        return "Attempt \(attempt) / Goal \(progress.goal)"
    }
    var subjectLabel: String { subject }
    var phaseLabel: String { phase }
    var provenanceLabel: String? { isDemo ? "SIMULATED" : nil }
}

/// Shared HUD shell for both automatic fixed-condition diagnostics.
struct DiagnosticHUD: View {
    let presentation: DiagnosticHUDPresentation
    let trackingConfidence: Double
    let isPaused: Bool
    let assistedActionTitle: String
    let assistedActionEnabled: Bool
    let onAssistedStep: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(presentation.attemptLabel)
                .font(.title2.bold())
            Text(presentation.subjectLabel)
                .font(.headline)
            if isPaused {
                Label("Tracking paused — partial attempt discarded", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text(presentation.phaseLabel)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: presentation.progress.partial)
            Text("Tracking confidence \(Int((trackingConfidence * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if presentation.progress.completed < presentation.progress.goal {
                Button(assistedActionTitle, action: onAssistedStep)
                    .buttonStyle(.borderedProminent)
                    .disabled(!assistedActionEnabled)
                Text("ASSISTED — NOT TRACKED")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            if let provenanceLabel = presentation.provenanceLabel {
                Text(provenanceLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 430)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
