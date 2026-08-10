import Observation
import RealityKit
import SwiftUI

private final class BalanceSubscriptionHolder {
    var update: EventSubscription?
}

enum BalancePlatformPlacement {
    static func position(viewerPosition: SIMD3<Float>?) -> SIMD3<Float> {
        guard let viewerPosition else { return [0, 0.9, -1] }
        return [0, min(max(viewerPosition.y - 0.25, 0.72), 1.20), -1]
    }
}

struct BalancePlatformPlacementLatch {
    private(set) var position: SIMD3<Float>?

    mutating func lock(viewerPosition: SIMD3<Float>?) -> SIMD3<Float> {
        if let position {
            return position
        }
        let lockedPosition = BalancePlatformPlacement.position(viewerPosition: viewerPosition)
        position = lockedPosition
        return lockedPosition
    }
}

struct BalanceInputChronology: Equatable, Sendable {
    private var lastTimestamp: TimeInterval?

    mutating func consume(_ frame: HandJointFrame?) -> HandJointFrame? {
        guard let frame,
              frame.timestamp.isFinite,
              lastTimestamp.map({ frame.timestamp > $0 }) ?? true else {
            return nil
        }
        lastTimestamp = frame.timestamp
        return frame
    }

    func nextTimestamp(startingAt candidate: TimeInterval) -> TimeInterval {
        guard let lastTimestamp else { return candidate }
        return max(candidate, lastTimestamp + 1.0 / 60.0)
    }
}

struct BalanceViewTrackingState: Equatable, Sendable {
    private var chronology = BalanceInputChronology()
    private(set) var recalibrationGeneration: Int?
    private var handledResetGeneration: Int?
    private var acknowledgedCalibrationGeneration: Int?

    mutating func beginProcessorReset(generation: Int) -> Bool {
        guard handledResetGeneration != generation else { return false }
        handledResetGeneration = generation
        acknowledgedCalibrationGeneration = nil
        recalibrationGeneration = generation
        return true
    }

    mutating func takeCalibrationAcknowledgement(generation: Int) -> Bool {
        guard recalibrationGeneration == generation,
              acknowledgedCalibrationGeneration != generation else {
            return false
        }
        acknowledgedCalibrationGeneration = generation
        return true
    }

    mutating func consume(_ frame: HandJointFrame?) -> HandJointFrame? {
        chronology.consume(frame)
    }

    func nextTimestamp(startingAt candidate: TimeInterval) -> TimeInterval {
        chronology.nextTimestamp(startingAt: candidate)
    }

    mutating func finishRecalibration() {
        recalibrationGeneration = nil
    }
}

enum BalanceFallbackRepAction {
    @MainActor
    static func process(
        source: SyntheticMovementSource,
        nextTimestamp: inout TimeInterval,
        trackingState: inout BalanceViewTrackingState,
        session: inout BalanceSession
    ) -> BalanceEvent {
        nextTimestamp = trackingState.nextTimestamp(startingAt: nextTimestamp)
        while !session.isCalibrated {
            source.setBalanceCalibrationPose(at: nextTimestamp)
            nextTimestamp += 1.0 / 60.0
            guard let frame = trackingState.consume(source.latestJointFrame) else {
                return .paused
            }
            _ = session.process(
                frame: frame,
                ballPosition: BalanceTargetSchedule.ballStart,
                ballEscaped: false
            )
        }
        source.setBalanceCalibrationPose(at: nextTimestamp)
        nextTimestamp += 1.0 / 60.0
        guard let frame = trackingState.consume(source.latestJointFrame) else {
            return .paused
        }
        return session.process(
            frame: frame,
            ballPosition: session.currentTarget.position,
            ballEscaped: false
        )
    }
}

enum BalanceFallbackControl {
    static let title = "Complete Rep (Assisted)"

    static func isVisible(hasAuthorizedSession: Bool) -> Bool {
        hasAuthorizedSession
    }

    static func isEnabled(hasAuthorizedSession: Bool, isComplete: Bool) -> Bool {
        hasAuthorizedSession && !isComplete
    }

    static func isSessionAuthorized(_ phase: RehabSessionPhase) -> Bool {
        let request: RehabSessionRequest
        switch phase {
        case let .active(activeRequest, _, _), let .paused(activeRequest, _, _):
            request = activeRequest
        case .idle, .starting, .failed, .completed:
            return false
        }
        return request.experience == .exercise(.balance)
    }
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
    @State private var trackingState = BalanceViewTrackingState()
    @State private var demoSource: SyntheticMovementSource
    @State private var nextDemoCalibrationTimestamp: TimeInterval = 1.0 / 60.0
    @State private var placementLatch = BalancePlatformPlacementLatch()

    private let hudOffset = SIMD3<Float>(0, 0.28, 0.1)
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
        _demoSource = State(initialValue: SyntheticMovementSource(hand: request.affectedHand))
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
            let lockedTrayPosition = placementLatch.lock(
                viewerPosition: coordinator.currentViewerPosition
            )
            let root = Entity()
            root.name = "BalancePlatformRoot"

            var simulation = PhysicsSimulationComponent()
            simulation.gravity = [0, -3, 0]
            root.components.set(simulation)

            buildTray()
            tray.position = lockedTrayPosition
            root.addChild(tray)

            hole = makeHole()
            tray.addChild(hole)

            ball = makeBall()
            root.addChild(ball)

            if let hud = attachments.entity(for: "balance-hud") {
                hud.position = lockedTrayPosition + hudOffset
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
                hud.position = trayPosition + hudOffset
                root.addChild(hud)
            }
        } attachments: {
            Attachment(id: "balance-hud") {
                let recovery = ImmersiveRecoveryPresentation.make(
                    phase: coordinator.phase,
                    canConfirmRecalibration: coordinator.canConfirmRecalibration
                )
                ImmersiveRecoveryStack(
                    presentation: recovery,
                    onRecalibrate: { _ = coordinator.confirmRecalibration() },
                    onBackToRoutine: coordinator.requestReturnToRoutine
                ) {
                    BalanceHUD(
                        progress: game.progress,
                        isCalibrated: game.isCalibrated,
                        calibrationProgress: game.calibrationProgress,
                        calibrationGoal: game.calibrationFrameGoal,
                        isRecovering: recovery != nil,
                        isDemo: coordinator.isUsingDemoMode,
                        showAssistedAction: BalanceFallbackControl.isVisible(
                            hasAuthorizedSession: hasAuthorizedBalanceSession
                        ),
                        assistedActionEnabled: BalanceFallbackControl.isEnabled(
                            hasAuthorizedSession: hasAuthorizedBalanceSession,
                            isComplete: game.isComplete
                        ),
                        onAssistedRep: completeAssistedRep
                    )
                }
            }
        }
    }

    private func gameStep(_ deltaTime: TimeInterval) {
        coordinator.updateRequiredJoints(game.requiredJoints)
        if processRecalibrationIfNeeded() {
            return
        }
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
            if let frame = nextTrackingFrame() {
                applyTrackingTiltWithoutScoring(frame: frame)
            }
            if respawnCountdown <= 0 {
                placeHoleAndBall()
            }
            return
        }

        guard let frame = nextTrackingFrame() else { return }

        let ballLocal = ball.position(relativeTo: tray)
        let planarPosition = SIMD2<Float>(ballLocal.x, ballLocal.z)
        let escaped = simd_distance(ball.position(relativeTo: nil), trayPosition) > trayRadius * 4
        handle(game.process(
            frame: frame,
            ballPosition: planarPosition,
            ballEscaped: escaped
        ))
    }

    private func processRecalibrationIfNeeded() -> Bool {
        if let generation = coordinator.pendingProcessorResetGeneration,
           trackingState.beginProcessorReset(generation: generation) {
            game.pause(requiresRecalibration: true)
            placeBallAtStart()
            freezeBall()
            _ = coordinator.acknowledgeProcessorReset(generation)
        }

        guard let generation = trackingState.recalibrationGeneration else { return false }
        guard case .trackingLost(requiresRecalibration: true) = coordinator.pauseReason else {
            trackingState.finishRecalibration()
            return false
        }
        guard let frame = trackingState.consume(coordinator.currentFrame) else {
            freezeBall()
            return true
        }

        _ = game.process(
            frame: frame,
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        )
        freezeBall()
        if game.isCalibrated,
           trackingState.takeCalibrationAcknowledgement(generation: generation) {
            coordinator.updateRequiredJoints(game.requiredJoints)
            _ = coordinator.acknowledgeProcessorCalibration(
                generation: generation,
                frameTimestamp: frame.timestamp
            )
        }
        return true
    }

    private func applyTrackingTiltWithoutScoring(frame: HandJointFrame) {
        handle(game.process(
            frame: frame,
            ballPosition: BalanceTargetSchedule.ballStart,
            ballEscaped: false
        ), allowScore: false)
    }

    private func nextTrackingFrame() -> HandJointFrame? {
        if coordinator.isUsingDemoMode, !game.isCalibrated {
            demoSource.setBalanceCalibrationPose(at: nextDemoCalibrationTimestamp)
            nextDemoCalibrationTimestamp += 1.0 / 60.0
            return trackingState.consume(demoSource.latestJointFrame)
        }
        return trackingState.consume(coordinator.currentFrame)
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

    private var trayPosition: SIMD3<Float> {
        placementLatch.position ?? BalancePlatformPlacement.position(viewerPosition: nil)
    }

    private var hasAuthorizedBalanceSession: Bool {
        BalanceFallbackControl.isSessionAuthorized(coordinator.phase)
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

    private func completeAssistedRep() {
        guard hasAuthorizedBalanceSession, ballActive, !game.isComplete else { return }
        let previousCompleted = game.progress.completed
        let target = game.currentTarget
        ball.setPosition([target.x, ballRestY, target.z], relativeTo: tray)
        if var motion = ball.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
            ball.components.set(motion)
        }
        let event = BalanceFallbackRepAction.process(
            source: demoSource,
            nextTimestamp: &nextDemoCalibrationTimestamp,
            trackingState: &trackingState,
            session: &game
        )
        _ = coordinator.registerAssistedProgress(
            from: previousCompleted,
            to: game.progress.completed
        )
        handle(event)
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
    let calibrationProgress: Int
    let calibrationGoal: Int
    let isRecovering: Bool
    let isDemo: Bool
    let showAssistedAction: Bool
    let assistedActionEnabled: Bool
    let onAssistedRep: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            SessionProgressLabel(progress: progress)
            if !isRecovering && !isCalibrated {
                Label("Hold your prescribed hand level", systemImage: "hand.raised")
                Text("Hold level: \(calibrationProgress) / \(calibrationGoal)")
                    .font(.headline.monospacedDigit())
                Text("Keep all four knuckles straight and level to calibrate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !isRecovering && progress.completed == progress.goal {
                Label("Prescribed dose complete", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if !isRecovering {
                Text("Tilt your wrist to roll the ball into the hole")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showAssistedAction {
                Button(BalanceFallbackControl.title, action: onAssistedRep)
                    .buttonStyle(.borderedProminent)
                    .disabled(!assistedActionEnabled)
                Text("ASSISTED — NOT TRACKED")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            if isDemo {
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
