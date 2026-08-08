import SwiftUI

struct ExerciseDemoView: View {
    let exercise: ExerciseKind
    let prescription: Prescription
    let useDemoFallback: Bool
    let onComplete: (GameplayResult) -> Void
    let onCancel: () -> Void

    @State private var started = false
    @State private var balance: BalanceSession
    @State private var squeeze: SqueezeSession
    @State private var closure: Float = 0

    init(
        exercise: ExerciseKind,
        prescription: Prescription,
        useDemoFallback: Bool,
        onComplete: @escaping (GameplayResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.exercise = exercise
        self.prescription = prescription
        self.useDemoFallback = useDemoFallback
        self.onComplete = onComplete
        self.onCancel = onCancel
        _balance = State(initialValue: BalanceSession(
            correctionsPerDirection: prescription.balanceCorrectionsPerDirection,
            requiredHoldSeconds: prescription.balanceHoldSeconds
        ))
        _squeeze = State(initialValue: SqueezeSession(
            repetitions: prescription.squeezeRepetitions,
            closeThreshold: prescription.squeezeCloseThreshold,
            reopenThreshold: prescription.squeezeReopenThreshold,
            holdSeconds: prescription.squeezeHoldSeconds
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            if !started {
                Text(exercise.title).font(.largeTitle.bold())
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
                BalancePlatformView(direction: balance.currentDirection, progress: balance.progress, trackingVisible: true)
                fallbackDisclosure
                Button("Hold centre (demo tracking)") {
                    let done = balance.registerCentreHold(seconds: prescription.balanceHoldSeconds, isTracked: true)
                    if done { onComplete(.fixture(for: .balance)) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                SqueezeBuddyView(
                    closure: closure,
                    phase: squeeze.phase,
                    completedRepetitions: squeeze.completedRepetitions,
                    prescribedRepetitions: squeeze.prescribedRepetitions,
                    trackingVisible: true
                )
                fallbackDisclosure
                Button("Complete close–hold–open (demo tracking)") {
                    let start = Double(squeeze.completedRepetitions) * 2
                    closure = 0.85
                    _ = squeeze.update(closure: closure, at: start, isTracked: true)
                    _ = squeeze.update(closure: closure, at: start + prescription.squeezeHoldSeconds + 0.1, isTracked: true)
                    closure = 0.15
                    let done = squeeze.update(closure: closure, at: start + prescription.squeezeHoldSeconds + 0.2, isTracked: true)
                    if done { onComplete(.fixture(for: .squeeze)) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(40)
    }

    private var introduction: String {
        exercise == .balance
            ? "Guide the ball to centre for one prescribed correction in each direction."
            : "Use your physical stress ball. Vision Pro observes hand closing and reopening, not grip force."
    }

    private var fallbackDisclosure: some View {
        Text(useDemoFallback ? "DEMO FALLBACK — synthetic observations use the same detectors" : "LIVE HAND TRACKING")
            .font(.caption.bold())
            .foregroundStyle(useDemoFallback ? .orange : .green)
    }
}
