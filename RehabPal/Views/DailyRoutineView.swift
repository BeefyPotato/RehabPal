import SwiftUI

struct DailyRoutineView: View {
    let state: AppState
    let startExercise: (ExerciseKind) -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text("Today's routine")
                .font(.largeTitle.bold())
            Text("Complete both exercises in either order. Your physiotherapist has already set the targets.")
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                exerciseCard(.balance, dose: "8 ball-in-hole repetitions")
                exerciseCard(.squeeze, dose: "\(state.prescription.squeezeRepetitions) close–hold–open reps")
            }
            Text(state.canStartAssessment ? "Daily assessment unlocked" : "Daily assessment unlocks after both exercises")
                .foregroundStyle(state.canStartAssessment ? .green : .secondary)
        }
        .padding(50)
    }

    private func exerciseCard(_ exercise: ExerciseKind, dose: String) -> some View {
        let complete = state.completedExercises.contains(exercise)
        return VStack(alignment: .leading, spacing: 18) {
            Image(systemName: exercise == .balance ? "circle.grid.cross" : "hand.raised.fingers.spread")
                .font(.system(size: 44))
            Text(exercise.title).font(.title.bold())
            Text(dose).foregroundStyle(.secondary)
            Button(complete ? "Completed" : "Start") { startExercise(exercise) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(complete)
        }
        .padding(28)
        .frame(width: 330, height: 260, alignment: .leading)
        .glassBackgroundEffect()
    }
}
