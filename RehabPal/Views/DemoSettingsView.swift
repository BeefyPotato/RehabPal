import SwiftUI

struct DemoSettingsView: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Button("Simulate one day passing") {
                    state.simulatePetDay()
                }
                Text("RehabPal always tries live hand tracking first. If startup fails, the session offers Retry or an explicitly labeled Demo Mode; it never switches to simulated input silently.")
                    .foregroundStyle(.secondary)
                Text("Tracking loss pauses active progress, discards partial movement, and requires recalibration after two seconds.")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Demo settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .frame(minWidth: 600, minHeight: 420)
    }
}
