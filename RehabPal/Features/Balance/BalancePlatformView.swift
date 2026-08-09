import Observation
import RealityKit
import SwiftUI

private final class BalanceSubscriptionHolder {
    var update: EventSubscription?
}

/// The physical balance game rendered inside the app's one shared mixed space.
struct BalancePlatformView: View {
    let coordinator: RehabSessionCoordinator
    let onProgress: (SessionProgress) -> Void
    let onComplete: (GameplayResult) -> Void

    @State private var game: BalanceSession
    @State private var tray = Entity()
    @State private var ball = ModelEntity()
    @State private var hole = ModelEntity()
    @State private var subscriptions = BalanceSubscriptionHolder()
    @State private var ballActive = false
    @State private var respawnCountdown: TimeInterval = 0

    private let trayPosition = SIMD3<Float>(0, 0.9, -1)
    private let trayRadius: Float = 0.12
    private let wallHeight: Float = 0.025
    private let floorThickness: Float = 0.006
    private let ballRadius: Float = 0.014
    private let tiltGain: Float = 0.6
    private let tiltSmoothing: Float = 0.08

    init(
        request: RehabSessionRequest,
        coordinator: RehabSessionCoordinator,
        seed: UInt64 = .random(in: UInt64.min...UInt64.max),
        onProgress: @escaping (SessionProgress) -> Void,
        onComplete: @escaping (GameplayResult) -> Void
    ) {
        self.coordinator = coordinator
        self.onProgress = onProgress
        self.onComplete = onComplete
        _game = State(initialValue: BalanceSession(
            affectedHand: request.affectedHand,
            goal: request.goal,
            seed: seed,
            isSimulated: coordinator.isUsingDemoMode
        ))
    }

    private var ballRestY: Float { floorThickness / 2 + ballRadius + 0.002 }
    private var ballStartLocal: SIMD3<Float> {
        [BalanceTargetSchedule.ballStart.x, ballRestY, BalanceTargetSchedule.ballStart.y]
    }

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "BalancePlatformRoot"

            var simulation = PhysicsSimulationComponent()
            simulation.gravity = [0, -3, 0]
            root.components.set(simulation)

            buildTray()
            tray.position = trayPosition
            root.addChild(tray)

            hole = makeHole()
            tray.addChild(hole)

            ball = makeBall()
            root.addChild(ball)

            if let hud = attachments.entity(for: "balance-hud") {
                hud.position = [0, 1.18, -0.9]
                root.addChild(hud)
            }

            content.add(root)
            placeHoleAndBall()
            setBallDynamic(false)

            subscriptions.update = content.subscribe(to: SceneEvents.Update.self) { event in
                gameStep(event.deltaTime)
            }
        } update: { content, attachments in
            if let hud = attachments.entity(for: "balance-hud"),
               hud.parent == nil,
               let root = content.entities.first {
                hud.position = [0, 1.18, -0.9]
                root.addChild(hud)
            }
        } attachments: {
            Attachment(id: "balance-hud") {
                BalanceHUD(
                    progress: game.progress,
                    isCalibrated: game.isCalibrated,
                    pauseReason: coordinator.pauseReason,
                    isDemo: coordinator.isUsingDemoMode,
                    onDemoDrop: placeDemoBallInHole
                )
            }
        }
    }

    private func gameStep(_ deltaTime: TimeInterval) {
        guard case let .active(request, _, _) = coordinator.phase,
              request.experience == .exercise(.balance) else {
            let requiresRecalibration: Bool
            if case .trackingLost(requiresRecalibration: true) = coordinator.pauseReason {
                requiresRecalibration = true
            } else {
                requiresRecalibration = false
            }
            game.pause(requiresRecalibration: requiresRecalibration)
            freezeBall()
            return
        }

        if respawnCountdown > 0 {
            respawnCountdown -= deltaTime
            applyTrackingTiltWithoutScoring()
            if respawnCountdown <= 0 {
                placeHoleAndBall()
            }
            return
        }

        let ballLocal = ball.position(relativeTo: tray)
        let planarPosition = SIMD2<Float>(ballLocal.x, ballLocal.z)
        let escaped = simd_distance(ball.position(relativeTo: nil), trayPosition) > trayRadius * 4
        handle(game.process(
            frame: coordinator.currentFrame,
            ballPosition: planarPosition,
            ballEscaped: escaped
        ))
    }

    private func applyTrackingTiltWithoutScoring() {
        handle(game.process(
            frame: coordinator.currentFrame,
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        ), allowScore: false)
    }

    private func handle(_ event: BalanceEvent, allowScore: Bool = true) {
        switch event {
        case .waitingForCalibration, .paused:
            freezeBall()
        case let .active(tilt):
            applyTrayTilt(tilt)
            setBallDynamic(true)
        case let .resetBall(tilt):
            applyTrayTilt(tilt)
            placeBallAtStart()
            setBallDynamic(true)
        case let .scored(_, _, tilt, isComplete):
            applyTrayTilt(tilt)
            guard allowScore else { return }
            ballActive = false
            ball.isEnabled = false
            onProgress(game.progress)
            if isComplete, let result = game.result {
                hole.isEnabled = false
                onComplete(result)
            } else {
                respawnCountdown = 0.8
            }
        }
    }

    private func applyTrayTilt(_ tilt: WristTilt) {
        let pitch = simd_quatf(angle: tilt.pitch * tiltGain, axis: [1, 0, 0])
        let roll = simd_quatf(angle: -tilt.roll * tiltGain, axis: [0, 0, 1])
        let target = pitch * roll
        let smoothed = simd_slerp(tray.orientation, target, tiltSmoothing)
        var transform = Transform()
        transform.translation = trayPosition
        transform.rotation = smoothed
        tray.setTransformMatrix(transform.matrix, relativeTo: nil)
    }

    private func placeHoleAndBall() {
        let target = game.currentTarget
        hole.setPosition([target.x, floorThickness / 2 + 0.0015, target.z], relativeTo: tray)
        hole.isEnabled = true
        placeBallAtStart()
        ball.isEnabled = true
        ballActive = true
        setBallDynamic(game.isCalibrated)
    }

    private func placeBallAtStart() {
        ball.setPosition(ballStartLocal, relativeTo: tray)
        if var motion = ball.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
            ball.components.set(motion)
        }
    }

    private func freezeBall() {
        if var motion = ball.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
            ball.components.set(motion)
        }
        setBallDynamic(false)
    }

    private func setBallDynamic(_ dynamic: Bool) {
        guard var body = ball.components[PhysicsBodyComponent.self] else { return }
        body.mode = dynamic ? .dynamic : .kinematic
        ball.components.set(body)
    }

    private func placeDemoBallInHole() {
        guard coordinator.isUsingDemoMode, ballActive, !game.isComplete else { return }
        let target = game.currentTarget
        ball.setPosition([target.x, ballRestY, target.z], relativeTo: tray)
        if var motion = ball.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
            ball.components.set(motion)
        }
    }

    private func buildTray() {
        tray.name = "balance-tray"
        let side = trayRadius * 2
        let floorSize = SIMD3<Float>(side, floorThickness, side)
        let floor = ModelEntity(
            mesh: .generateBox(size: floorSize),
            materials: [SimpleMaterial(color: .init(white: 0.85, alpha: 1), isMetallic: false)]
        )
        floor.name = "balance-floor"
        addKinematicPhysics(to: floor, shape: .generateBox(size: floorSize))
        tray.addChild(floor)

        let wallThickness: Float = 0.006
        let wallY = floorThickness / 2 + wallHeight / 2
        let offset = trayRadius - wallThickness / 2
        let specs: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([side, wallHeight, wallThickness], [0, wallY, offset]),
            ([side, wallHeight, wallThickness], [0, wallY, -offset]),
            ([wallThickness, wallHeight, side], [offset, wallY, 0]),
            ([wallThickness, wallHeight, side], [-offset, wallY, 0])
        ]
        for (index, spec) in specs.enumerated() {
            let wall = ModelEntity(
                mesh: .generateBox(size: spec.0),
                materials: [SimpleMaterial(color: .init(white: 0.6, alpha: 1), isMetallic: false)]
            )
            wall.name = "balance-wall-\(index)"
            wall.position = spec.1
            addKinematicPhysics(to: wall, shape: .generateBox(size: spec.0))
            tray.addChild(wall)
        }
    }

    private func makeHole() -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: 0.002, radius: BalanceSession.holeRadius),
            materials: [SimpleMaterial(color: .init(white: 0.05, alpha: 1), isMetallic: false)]
        )
        entity.name = "balance-hole"
        return entity
    }

    private func makeBall() -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: ballRadius),
            materials: [SimpleMaterial(color: .systemOrange, roughness: 0.3, isMetallic: true)]
        )
        entity.name = "balance-ball"
        let shape = ShapeResource.generateSphere(radius: ballRadius)
        var body = PhysicsBodyComponent(
            shapes: [shape],
            mass: 0.05,
            material: .generate(staticFriction: 0.7, dynamicFriction: 0.6, restitution: 0.05),
            mode: .dynamic
        )
        body.linearDamping = 1.2
        body.angularDamping = 1.2
        entity.components.set(body)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(PhysicsMotionComponent())
        return entity
    }

    private func addKinematicPhysics(to entity: ModelEntity, shape: ShapeResource) {
        let body = PhysicsBodyComponent(
            shapes: [shape],
            mass: 1,
            material: .generate(staticFriction: 0.7, dynamicFriction: 0.6, restitution: 0.05),
            mode: .kinematic
        )
        entity.components.set(body)
        entity.components.set(CollisionComponent(shapes: [shape]))
    }
}

private struct BalanceHUD: View {
    let progress: SessionProgress
    let isCalibrated: Bool
    let pauseReason: SessionPauseReason?
    let isDemo: Bool
    let onDemoDrop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            SessionProgressLabel(progress: progress)
            if pauseReason != nil {
                Label("Tracking paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else if !isCalibrated {
                Label("Hold your prescribed hand level", systemImage: "hand.raised")
                Text("Keep all four knuckles straight and level to calibrate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if progress.completed == progress.goal {
                Label("Prescribed dose complete", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Tilt your wrist to roll the ball into the hole")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isDemo, progress.completed < progress.goal {
                Button("Drop ball (Demo Mode)", action: onDemoDrop)
                    .buttonStyle(.borderedProminent)
                Text("SIMULATED")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
