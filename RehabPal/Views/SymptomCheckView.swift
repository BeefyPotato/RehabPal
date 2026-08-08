import SwiftUI

struct SymptomCheckView: View {
    let state: AppState
    @State private var discomfort = 2.0
    @State private var stiffness = 3.0
    @State private var difficulty = 2.0
    @State private var increased = false
    @State private var catching = false

    var body: some View {
        Form {
            Section("How do you feel now?") {
                score("Pain or discomfort", value: $discomfort)
                score("Stiffness", value: $stiffness)
                score("Difficulty", value: $difficulty)
                Toggle("Pain increased compared with before", isOn: $increased)
                Toggle("Catching or locking", isOn: $catching)
            }
            Section {
                Button("Submit check-in") {
                    _ = state.submitSymptoms(SymptomResult(
                        discomfort: Int(discomfort),
                        increasedSinceStart: increased,
                        stiffness: Int(stiffness),
                        difficulty: Int(difficulty),
                        catchingOrLocking: catching
                    ))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700, height: 650)
    }

    private func score(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int(value.wrappedValue))/10")
            Slider(value: value, in: 0...10, step: 1)
        }
    }
}
