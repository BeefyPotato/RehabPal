import RealityKit
import RealityKitContent
import SwiftUI

struct HomeView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 24) {
            RealityView { content in
                content.add(await RehabPalAssets.loadPet())
            }
            .frame(width: 300, height: 235)
                .accessibilityLabel("Recovery Pet")
            Text("Good to see you")
                .font(.largeTitle.bold())
            Text("Your Recovery Pet is ready for today's prescribed routine.")
                .font(.title3)
                .foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Hunger", systemImage: "fork.knife")
                        Spacer()
                        Text("\(Int(state.hunger.fullness.rounded()))% full")
                    }
                    ProgressView(value: state.hunger.fullness, total: 100)
                        .tint(state.hunger.fullness < 25 ? .orange : .green)
                        .accessibilityValue("\(Int(state.hunger.fullness.rounded())) percent full")
                }
                .task(id: context.date) { state.resolvePetHunger(at: context.date) }
            }
            HStack(spacing: 28) {
                Label("\(state.history.currentStreak)-day streak", systemImage: "flame.fill")
                Label("2 exercises", systemImage: "checklist")
            }
            .font(.headline)
            Button("Start Daily Routine") {
                _ = state.startRoutine()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
        }
        .padding(60)
        .frame(maxWidth: 760)
    }
}

struct FullForTodayView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("😊🐾")
                .font(.system(size: 92))
            Text("Full for today")
                .font(.largeTitle.bold())
            Text("You completed the prescribed dose. More repetitions won't earn extra treats—rest is part of the routine.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 650)
            Button("Reset Demo Day") { state.resetDemoDay() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(60)
    }
}
