import SwiftUI

struct ExerciseDemoView: View {
    let exercise: ExerciseKind
    let prescription: Prescription
    let useDemoFallback: Bool
    let onBegin: () -> Void
    let onCancel: () -> Void

    @State private var started = false

    init(
        exercise: ExerciseKind,
        prescription: Prescription,
        useDemoFallback: Bool,
        onBegin: @escaping () -> Void = {},
        onCancel: @escaping () -> Void
    ) {
        self.exercise = exercise
        self.prescription = prescription
        self.useDemoFallback = useDemoFallback
        self.onBegin = onBegin
        self.onCancel = onCancel
        _started = State(initialValue: false)
    }

    var body: some View {
        VStack(spacing: 20) {
            if !started {
                Text(exercise.title).font(.largeTitle.bold())
                InstructionMediaCard(kind: mediaKind)
                Text(introduction)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 650)
                Label("Stay seated and move only within your comfortable prescribed range.", systemImage: "figure.seated.seatbelt")
                Button("Begin prescribed dose") {
                    started = true
                    onBegin()
                }
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
            } else if exercise == .squeeze {
                Text("The inferred real-ball Squeeze Buddy is active in the immersive space.")
                    .font(.title2.weight(.semibold))
                Text("Cup your prescribed hand around the physical stress ball. The floating face appears only after a stable grasp pose is detected.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                fallbackDisclosure
            } else {
                Text("Sheep Drop is active in the immersive space.")
                    .font(.title2.weight(.semibold))
                Text("Bring all five fingertips together around the sheep, carry it over the fenced pen, then spread your fingers to release. RehabPal infers this pose from fingertip positions; it does not force-measure your hand.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                fallbackDisclosure
            }
        }
        .padding(40)
    }

    private var introduction: String {
        switch exercise {
        case .balance:
            "Tilt your wrist to guide the ball into \(prescription.balanceTargetCount) changing holes."
        case .squeeze:
            "Pick up your real stress ball for \(prescription.squeezeRepetitions) close–hold–reopen repetitions. RehabPal observes motion, never grip force."
        case .sheepDrop:
            "Bring all five fingertips together around each sheep for \(prescription.sheepDropRepetitions) settled sheep placements. RehabPal infers the five-fingertip pose; it does not force-measure your hand."
        }
    }

    private var mediaKind: InstructionMediaKind {
        switch exercise {
        case .balance: .balance
        case .squeeze: .squeeze
        case .sheepDrop: .sheepDrop
        }
    }

    private var fallbackDisclosure: some View {
        Text(useDemoFallback ? "DEMO FALLBACK — synthetic observations use the same detectors" : "LIVE HAND TRACKING")
            .font(.caption.bold())
            .foregroundStyle(useDemoFallback ? .orange : .green)
    }

}
