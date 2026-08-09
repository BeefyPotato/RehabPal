import SwiftUI

struct DemoSettingsView: View {
    let state: AppState
    @Binding var useDemoFallback: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Use clearly labeled demo fallback", isOn: $useDemoFallback)
                Button("Simulate one day passing") {
                    state.simulatePetDay()
                }
                Text("Fallback injects synthetic wrist and hand observations through the same detectors. It cannot bypass medication, exercise, assessment, symptom, report, or pet gates.")
                    .foregroundStyle(.secondary)
                Text("On device, turn fallback off and grant hand-tracking permission. Tracking loss pauses active progress.")
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
