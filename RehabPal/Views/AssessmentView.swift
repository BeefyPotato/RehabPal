import SwiftUI

struct AssessmentView: View {
    let state: AppState
    let useDemoFallback: Bool
    @State private var step = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Daily assessment")
                .font(.largeTitle.bold())
            Text("Fixed conditions every demo day")
                .font(.title2)
            Text(step == 0
                 ? "Two attempts each: centre, forward, backward, left, and right."
                 : "Five paced repetitions: 2 seconds close, 1 second hold, 2 seconds release.")
                .multilineTextAlignment(.center)
            Label(useDemoFallback ? "Demo fallback active" : "Live hand tracking", systemImage: "hand.raised")
                .foregroundStyle(useDemoFallback ? .orange : .green)
            Button(step == 0 ? "Complete fixed wrist checks" : "Complete fixed hand checks") {
                if step == 0 { step = 1 } else { _ = state.completeAssessment(.fixture) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            Text("App-estimated movement measures; not clinical goniometer or strength measurements.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(60)
    }
}
