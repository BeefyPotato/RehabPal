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
