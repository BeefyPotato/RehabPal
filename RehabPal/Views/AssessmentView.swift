import SwiftUI

struct WristAssessmentView: View {
    let useDemoFallback: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("Daily assessment")
                .font(.largeTitle.bold())
            Text("Fixed conditions every demo day")
                .font(.title2)
            InstructionMediaCard(kind: .wristAssessment)
            Text("Two automatic attempts each: center, forward, backward, left, and right.")
                .multilineTextAlignment(.center)
            Label(useDemoFallback ? "Demo fallback active" : "Live hand tracking", systemImage: "hand.raised")
                .foregroundStyle(useDemoFallback ? .orange : .green)
            ProgressView()
            Text("Follow the prompts in the immersive diagnostic.")
                .foregroundStyle(.secondary)
            Text("App-estimated movement measures; not clinical goniometer or strength measurements.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(60)
    }
}

struct HandROMAssessmentView: View {
    let useDemoFallback: Bool

    var body: some View {
        VStack(spacing: 22) {
            Text("Hand range of motion").font(.largeTitle.bold())
            InstructionMediaCard(kind: .fingerROM)
            Text("The immersive diagnostic advances automatically through two attempts for all five digits.")
                .font(.title2).multilineTextAlignment(.center)
            Label(useDemoFallback ? "Demo values active" : "HandTrackingProvider joint tracking", systemImage: "hand.raised")
                .foregroundStyle(useDemoFallback ? .orange : .green)
            ProgressView()
            Text("Extend, flex, and return the prompted digit.")
                .foregroundStyle(.secondary)
            Text("App-estimated joint excursion for comparison; not a clinical goniometer measurement.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(50)
    }
}
