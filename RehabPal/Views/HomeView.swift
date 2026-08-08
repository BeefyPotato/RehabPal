import SwiftUI

struct HomeView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("🐾")
                .font(.system(size: 96))
                .accessibilityLabel("Recovery Pet")
            Text("Good to see you")
                .font(.largeTitle.bold())
            Text("Your Recovery Pet is ready for today's prescribed routine.")
                .font(.title3)
                .foregroundStyle(.secondary)
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
