import SwiftUI

struct ContentView: View {
    @State private var state = AppState()
    @State private var selectedExercise: ExerciseKind?
    @State private var handTracking = HandTrackingEngine()
    @State private var showingSettings = false
    @State private var useDemoFallback = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch DemoRouter.screen(for: state) {
                case .home:
                    HomeView(state: state)
                case .medication:
                    MedicationGateView(state: state)
                case .routine:
                    if let selectedExercise {
                        ExerciseDemoView(
                            exercise: selectedExercise,
                            prescription: state.prescription,
                            useDemoFallback: useDemoFallback,
                            liveObservation: handTracking.latestObservation
                        ) { result in
                            _ = state.completeExercise(selectedExercise, result: result)
                            self.selectedExercise = nil
                        } onCancel: {
                            self.selectedExercise = nil
                        }
                    } else {
                        DailyRoutineView(state: state) { selectedExercise = $0 }
                    }
                case .assessment:
                    AssessmentView(state: state, useDemoFallback: useDemoFallback)
                case .symptoms:
                    SymptomCheckView(state: state)
                case .report:
                    AfterCareReportView(state: state)
                case .petReward:
                    PetRewardView(state: state)
                case .complete:
                    FullForTodayView(state: state)
                }
            }
            .animation(.easeInOut, value: state.stage)

            Button {
                showingSettings = true
            } label: {
                Label("Demo settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .padding(24)
        }
        .sheet(isPresented: $showingSettings) {
            DemoSettingsView(useDemoFallback: $useDemoFallback)
        }
        .task(id: useDemoFallback) {
            if !useDemoFallback {
                await handTracking.start()
            }
        }
    }
}

#Preview {
    ContentView()
}
