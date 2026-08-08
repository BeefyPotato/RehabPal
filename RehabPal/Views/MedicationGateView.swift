import SwiftUI

struct MedicationGateView: View {
    let state: AppState
    @State private var showedNoReminder = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "pills.circle")
                .font(.system(size: 72))
            Text("Have you taken your prescribed medication?")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Please follow the instructions already provided by your clinician.")
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Button("Not yet") {
                    _ = state.answerMedication(taken: false)
                    showedNoReminder = true
                }
                .buttonStyle(.bordered)
                Button("Yes, I have") {
                    _ = state.answerMedication(taken: true)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.extraLarge)
            if showedNoReminder {
                Text("Today's routine stays locked. Return after following your prescribed instructions.")
                    .padding()
                    .glassBackgroundEffect()
            }
        }
        .padding(60)
        .frame(maxWidth: 760)
    }
}
