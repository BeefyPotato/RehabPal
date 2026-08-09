import SwiftUI

struct ExerciseDemoView: View {
    let exercise: ExerciseKind
    let prescription: Prescription
    let useDemoFallback: Bool
    let liveObservation: MovementObservation
    let onComplete: (GameplayResult) -> Void
    let onCancel: () -> Void

    @State private var started = false
    @State private var squeeze: SqueezeSession
    @State private var closure: Float = 0
    @State private var completedResult: GameplayResult?

    init(
        exercise: ExerciseKind,
        prescription: Prescription,
        useDemoFallback: Bool,
        liveObservation: MovementObservation,
        onComplete: @escaping (GameplayResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.exercise = exercise
        self.prescription = prescription
        self.useDemoFallback = useDemoFallback
        self.liveObservation = liveObservation
        self.onComplete = onComplete
        self.onCancel = onCancel
        _started = State(initialValue: exercise == .balance)
        _squeeze = State(initialValue: SqueezeSession(
            repetitions: prescription.squeezeRepetitions,
            closeThreshold: prescription.squeezeCloseThreshold,
            reopenThreshold: prescription.squeezeReopenThreshold,
            holdSeconds: prescription.squeezeHoldSeconds
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            if let completedResult {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
                Text("Prescribed dose complete").font(.largeTitle.bold())
                Text(exercise == .balance ? "\(completedResult.completedDose) targets reached" : "\(completedResult.completedDose) close–hold–open repetitions")
                    .font(.title2)
                Text("Return to today’s routine for your next step.").foregroundStyle(.secondary)
                Button("Continue") { onComplete(completedResult) }
                    .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            } else if !started {
                Text(exercise.title).font(.largeTitle.bold())
                InstructionMediaCard(kind: exercise == .balance ? .balance : .squeeze)
                Text(introduction)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 650)
                Label("Stay seated and move only within your comfortable prescribed range.", systemImage: "figure.seated.seatbelt")
                Button("Begin prescribed dose") { started = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                Button("Back", action: onCancel).buttonStyle(.borderless)
            } else if exercise == .balance {
                Text("The calibrated balance platform is active in the immersive space.")
                    .font(.title2.weight(.semibold))
                Text("Hold the prescribed hand level to calibrate, then tilt your wrist to guide each physics ball into its hole.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                fallbackDisclosure
            } else {
                SqueezeBuddyView(
                    closure: closure,
                    phase: squeeze.phase,
                    completedRepetitions: squeeze.completedRepetitions,
                    prescribedRepetitions: squeeze.prescribedRepetitions,
                    trackingVisible: useDemoFallback || liveObservation.isTracked
                )
                fallbackDisclosure
                if useDemoFallback {
                    Button("Complete close–hold–open (demo tracking)") {
                        let start = Double(squeeze.completedRepetitions) * 2
                        closure = 0.85
                        _ = squeeze.update(closure: closure, at: start, isTracked: true)
                        _ = squeeze.update(closure: closure, at: start + prescription.squeezeHoldSeconds + 0.1, isTracked: true)
                        closure = 0.15
                        let done = squeeze.update(closure: closure, at: start + prescription.squeezeHoldSeconds + 0.2, isTracked: true)
                        if done { finish(.squeeze) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(40)
        .onChange(of: liveObservation) { _, observation in
            guard started, !useDemoFallback else { return }
            consumeLiveObservation(observation)
        }
    }

    private var introduction: String {
        exercise == .balance
            ? "Tilt your wrist to guide the ball into \(prescription.balanceTargetCount) changing holes."
            : "Pick up your real stress ball. Close, hold gently, and fully reopen; RehabPal observes motion, never grip force."
    }

    private var fallbackDisclosure: some View {
        Text(useDemoFallback ? "DEMO FALLBACK — synthetic observations use the same detectors" : "LIVE HAND TRACKING")
            .font(.caption.bold())
            .foregroundStyle(useDemoFallback ? .orange : .green)
    }

    private func consumeLiveObservation(_ observation: MovementObservation) {
        if exercise == .squeeze {
            closure = observation.closure
            let done = squeeze.update(
                closure: observation.closure,
                at: observation.timestamp,
                isTracked: observation.isTracked
            )
            if done { finish(.squeeze) }
        }
    }

    private func finish(_ exercise: ExerciseKind) {
        completedResult = .fixture(for: exercise)
    }
}
