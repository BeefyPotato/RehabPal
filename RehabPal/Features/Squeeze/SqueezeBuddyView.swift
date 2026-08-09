import RealityKit
import SwiftUI

private final class SqueezeSubscriptionHolder {
    var update: EventSubscription?
}

/// An inferred overlay for the user's physical stress ball. The scene contains
/// facial features only; it intentionally never renders a virtual ball mesh.
struct SqueezeBuddyView: View {
    let coordinator: RehabSessionCoordinator
    let onProgress: (SessionProgress) -> Void
    let onComplete: (GameplayResult) -> Void

    @State private var game: SqueezeSession
    @State private var faceRoot = Entity()
    @State private var leftEye = ModelEntity()
    @State private var rightEye = ModelEntity()
    @State private var mouth = ModelEntity()
    @State private var subscriptions = SqueezeSubscriptionHolder()
    @State private var demoTimestamp: TimeInterval = 0

    init(
        request: RehabSessionRequest,
        coordinator: RehabSessionCoordinator,
        closeThreshold: Float,
        reopenThreshold: Float,
        holdSeconds: TimeInterval,
        onProgress: @escaping (SessionProgress) -> Void,
        onComplete: @escaping (GameplayResult) -> Void
    ) {
        self.coordinator = coordinator
        self.onProgress = onProgress
        self.onComplete = onComplete
        _game = State(initialValue: SqueezeSession(
            affectedHand: request.affectedHand,
            goal: request.goal,
            closeThreshold: closeThreshold,
            reopenThreshold: reopenThreshold,
            holdSeconds: holdSeconds,
            isSimulated: coordinator.isUsingDemoMode
        ))
    }

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "SqueezeOverlayRoot"
            buildFace()
            root.addChild(faceRoot)
            faceRoot.isEnabled = false

            if let hud = attachments.entity(for: "squeeze-hud") {
                hud.position = [0, 1.15, -0.8]
                root.addChild(hud)
            }
            content.add(root)
            subscriptions.update = content.subscribe(to: SceneEvents.Update.self) { _ in
                gameStep()
            }
        } update: { content, attachments in
            if let hud = attachments.entity(for: "squeeze-hud"),
               hud.parent == nil,
               let root = content.entities.first {
                hud.position = [0, 1.15, -0.8]
                root.addChild(hud)
            }
            updateFace()
        } attachments: {
            Attachment(id: "squeeze-hud") {
                SqueezeHUD(
                    progress: game.progress,
                    phase: game.phase,
                    statusLabel: game.statusLabel,
                    faceVisible: game.facePose != nil,
                    pauseReason: coordinator.pauseReason,
                    isDemo: coordinator.isUsingDemoMode,
                    onDemoStep: performDemoStep
                )
            }
        }
    }

    private func gameStep() {
        guard case let .active(request, _, _) = coordinator.phase,
              request.experience == .exercise(.squeeze) else {
            let requiresRecalibration: Bool
            if case .trackingLost(requiresRecalibration: true) = coordinator.pauseReason {
                requiresRecalibration = true
            } else {
                requiresRecalibration = false
            }
            game.pause(requiresRecalibration: requiresRecalibration)
            updateFace()
            return
        }
        guard !coordinator.isUsingDemoMode else { return }
        handle(game.process(frame: coordinator.currentFrame))
    }

    private func handle(_ event: SqueezeEvent) {
        updateFace()
        switch event {
        case .active:
            onProgress(game.progress)
        case let .repCompleted(_, _, isComplete):
            onProgress(game.progress)
            if isComplete, let result = game.result {
                onComplete(result)
            }
        case .waitingForGrasp, .stabilizingGrasp, .paused, .complete:
            break
        }
    }

    private func buildFace() {
        faceRoot.name = "inferred-real-ball-face"
        let dark = SimpleMaterial(color: .black, isMetallic: false)
        leftEye = ModelEntity(mesh: .generateSphere(radius: 0.006), materials: [dark])
        rightEye = ModelEntity(mesh: .generateSphere(radius: 0.006), materials: [dark])
        mouth = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.026, 0.004, 0.003), cornerRadius: 0.002),
            materials: [dark]
        )
        leftEye.name = "left-eye"
        rightEye.name = "right-eye"
        mouth.name = "mouth"
        leftEye.position = [-0.012, 0.009, 0]
        rightEye.position = [0.012, 0.009, 0]
        mouth.position = [0, -0.011, 0]
        faceRoot.addChild(leftEye)
        faceRoot.addChild(rightEye)
        faceRoot.addChild(mouth)
    }

    private func updateFace() {
        guard let pose = game.facePose else {
            faceRoot.isEnabled = false
            return
        }
        let viewerPosition = coordinator.currentViewerPosition ?? SIMD3<Float>(0, 1.4, 0)
        let position = pose.surfacePosition(toward: viewerPosition)
        faceRoot.isEnabled = true
        faceRoot.look(at: viewerPosition, from: position, relativeTo: nil, forward: .positiveZ)
        let expression = max(0.6, 1 - game.normalizedClosure * 0.35)
        leftEye.scale = [1, expression, 1]
        rightEye.scale = [1, expression, 1]
        mouth.scale = [1 + game.normalizedClosure * 0.45, expression, 1]
    }

    private func performDemoStep() {
        guard coordinator.isUsingDemoMode, !game.isComplete else { return }
        if game.facePose == nil {
            handle(game.process(sample: demoSample(closure: 0, at: demoTimestamp)))
            demoTimestamp += 1.05
            handle(game.process(sample: demoSample(closure: 0, at: demoTimestamp)))
            return
        }
        demoTimestamp += 0.1
        handle(game.process(sample: demoSample(closure: 1, at: demoTimestamp)))
        demoTimestamp += 0.8
        handle(game.process(sample: demoSample(closure: 1, at: demoTimestamp)))
        demoTimestamp += 0.1
        handle(game.process(sample: demoSample(closure: 0.5, at: demoTimestamp)))
        demoTimestamp += 0.1
        handle(game.process(sample: demoSample(closure: 0, at: demoTimestamp)))
    }

    private func demoSample(closure: Float, at timestamp: TimeInterval) -> SqueezeHandSample {
        SqueezeHandSample(
            hand: game.affectedHand,
            timestamp: timestamp,
            metrics: SqueezeHandMetrics(
                ballCenter: [0, 1.05, -0.55],
                radius: 0.04,
                meanTipToPalmDistance: 0.08 * (1 - closure * 0.5),
                meanFingerFlexion: 0.3 + (.pi / 2) * closure
            )
        )
    }
}

private struct SqueezeHUD: View {
    let progress: SessionProgress
    let phase: SqueezeRepDetector.Phase
    let statusLabel: String?
    let faceVisible: Bool
    let pauseReason: SessionPauseReason?
    let isDemo: Bool
    let onDemoStep: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            SessionProgressLabel(progress: progress)
            Text("Phase: \(phase.rawValue.capitalized)")
                .font(.headline)
            HStack(spacing: 6) {
                phaseStep("Close", active: phase == .closing)
                phaseStep("Hold", active: phase == .held)
                phaseStep("Reopen", active: phase == .reopening)
            }
            if pauseReason != nil {
                Label("Tracking paused — face hidden", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else if let statusLabel, faceVisible {
                Text(statusLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            } else {
                Text("Cup your prescribed hand around the real stress ball and hold still for 1 second")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            Text("Vision tracks hand motion; it does not measure grip force.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if isDemo, progress.completed < progress.goal {
                Button(faceVisible ? "Complete close–hold–reopen (Demo Mode)" : "Detect grasp (Demo Mode)", action: onDemoStep)
                    .buttonStyle(.borderedProminent)
                Text("SIMULATED")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 430)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private func phaseStep(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(active ? Color.orange : Color.secondary.opacity(0.18), in: Capsule())
    }
}
