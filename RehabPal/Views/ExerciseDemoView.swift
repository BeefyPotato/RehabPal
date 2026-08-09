import SwiftUI

struct ExerciseDemoView: View {
    let exercise: ExerciseKind
    let prescription: Prescription
    let useDemoFallback: Bool
    let liveObservation: MovementObservation
    let onComplete: (GameplayResult) -> Void
    let onCancel: () -> Void

    @State private var started = false
    @State private var balance: MovingHoleBalanceSession
    @State private var ballPosition = SIMD2<Float>.zero
    @State private var lastBalanceTimestamp: TimeInterval?
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
        _balance = State(initialValue: MovingHoleBalanceSession(seed: 20260809))
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
                Text(exercise == .balance ? "8 targets reached" : "\(completedResult.completedDose) close–hold–open repetitions")
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
                BalancePlatformView(
                    target: balance.currentTarget,
                    ballPosition: ballPosition,
                    progress: balance.progress,
                    trackingVisible: useDemoFallback || liveObservation.isTracked
                )
                fallbackDisclosure
                if useDemoFallback {
                    Button("Guide ball into hole (demo tracking)") {
                        ballPosition = balance.currentTarget.position
                        let start = Double(balance.completedRepetitions)
                        _ = balance.update(ballPosition: ballPosition, at: start, isTracked: true)
                        let done = balance.update(ballPosition: ballPosition, at: start + 0.51, isTracked: true)
                        ballPosition = .zero
                        if done { finish(.balance) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
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
            ? "Tilt your wrist to guide the ball into eight changing holes. Hold it there briefly to score each rep."
            : "Pick up your real stress ball. Close, hold gently, and fully reopen; RehabPal observes motion, never grip force."
    }

    private var fallbackDisclosure: some View {
        Text(useDemoFallback ? "DEMO FALLBACK — synthetic observations use the same detectors" : "LIVE HAND TRACKING")
            .font(.caption.bold())
            .foregroundStyle(useDemoFallback ? .orange : .green)
    }

    private func consumeLiveObservation(_ observation: MovementObservation) {
        if exercise == .balance {
            guard observation.isTracked else {
                lastBalanceTimestamp = nil
                _ = balance.update(ballPosition: ballPosition, at: observation.timestamp, isTracked: false)
                return
            }
            let delta = min(max(observation.timestamp - (lastBalanceTimestamp ?? observation.timestamp), 0), 0.05)
            lastBalanceTimestamp = observation.timestamp
            let velocity = SIMD2<Float>(observation.wristRoll, observation.wristPitch) * 0.38
            ballPosition += velocity * Float(delta)
            ballPosition.x = min(max(ballPosition.x, -0.235), 0.235)
            ballPosition.y = min(max(ballPosition.y, -0.16), 0.16)
            let completedBefore = balance.completedRepetitions
            let done = balance.update(ballPosition: ballPosition, at: observation.timestamp, isTracked: true)
            if balance.completedRepetitions > completedBefore { ballPosition = .zero }
            if done { finish(.balance) }
        } else {
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
