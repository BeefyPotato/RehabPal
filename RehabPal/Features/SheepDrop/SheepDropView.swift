import Foundation
import RealityKit
import SwiftUI
import simd

enum SheepDropSceneConfiguration {
    static let gravity = SIMD3<Float>(0, -6, 0)
    static let tableSize = SIMD3<Float>(1, 0.015, 0.7)
    static let penSide: Float = 0.36
    static let fenceHeight: Float = 0.07
    static let fenceThickness: Float = 0.012
    static let spawnPadSide: Float = 0.26
    static let spawnPadGap: Float = 0.025
    static let floorY: Float = 0
    static let sheepCollisionRadius: Float = 0.055
    static let sheepVisibleRadius: Float = 0.05
    static let safeHorizontalRadius: Float = 0.65
    static let safeMinimumY: Float = -0.15
    static let safeMaximumY: Float = 0.60

    static let spawnPosition = SIMD3<Float>(
        penSide / 2 + spawnPadGap + spawnPadSide / 2,
        floorY + sheepCollisionRadius,
        0
    )
}

struct SheepDropCoordinateSpace: Sendable {
    let tableTransform: simd_float4x4
    private let worldToTable: simd_float4x4

    init?(tableTransform: simd_float4x4) {
        guard Self.isFinite(tableTransform) else { return nil }
        let determinant = simd_determinant(tableTransform)
        guard determinant.isFinite, abs(determinant) > .ulpOfOne else { return nil }
        let inverse = tableTransform.inverse
        guard Self.isFinite(inverse) else { return nil }
        self.tableTransform = tableTransform
        worldToTable = inverse
    }

    func worldPosition(fromPenLocal position: SIMD3<Float>) -> SIMD3<Float> {
        Self.xyz(tableTransform * SIMD4<Float>(position, 1))
    }

    func penLocalPosition(fromWorld position: SIMD3<Float>) -> SIMD3<Float> {
        Self.xyz(worldToTable * SIMD4<Float>(position, 1))
    }

    func worldVelocity(fromPenLocal velocity: SIMD3<Float>) -> SIMD3<Float> {
        Self.xyz(tableTransform * SIMD4<Float>(velocity, 0))
    }

    func penLocalVelocity(fromWorld velocity: SIMD3<Float>) -> SIMD3<Float> {
        Self.xyz(worldToTable * SIMD4<Float>(velocity, 0))
    }

    func penLocalFrame(_ frame: HandJointFrame?) -> HandJointFrame? {
        guard let frame else { return nil }
        var localJoints: [HandJoint: HandJointSample] = [:]
        localJoints.reserveCapacity(frame.joints.count)
        for (joint, sample) in frame.joints {
            switch sample {
            case let .tracked(transform):
                let localTransform = worldToTable * transform
                guard Self.isFinite(localTransform) else { return nil }
                localJoints[joint] = .tracked(transform: localTransform)
            case .untracked:
                localJoints[joint] = .untracked
            }
        }
        return .synthetic(
            hand: frame.hand,
            timestamp: frame.timestamp,
            joints: localJoints
        )
    }

    private static func xyz(_ vector: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3<Float>(vector.x, vector.y, vector.z)
    }

    private static func isFinite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { column in
                column.x.isFinite && column.y.isFinite &&
                column.z.isFinite && column.w.isFinite
            }
    }
}

struct SheepDropPlacementState: Equatable, Sendable {
    private(set) var placement: TablePlacement?
    private(set) var isLocked = false

    mutating func receive(_ placement: TablePlacement) {
        guard !isLocked else { return }
        self.placement = placement
    }

    mutating func lockAtFirstPickup() {
        guard placement != nil else { return }
        isLocked = true
    }
}

struct SheepDropHUDPresentation: Equatable, Sendable {
    let provenanceLabel: String
    let tableLabel: String
    let instruction: String

    init(
        phase: SheepDropPhase,
        pauseReason: SessionPauseReason?,
        provenance: SessionProvenance?,
        tableSource: TablePlacement.Source?,
        isOverPen: Bool
    ) {
        provenanceLabel = provenance == .demo
            ? "DEMO FALLBACK — SIMULATED"
            : "LIVE HAND TRACKING"
        switch tableSource {
        case .detected:
            tableLabel = "TABLE DETECTED"
        case .estimated:
            tableLabel = "TABLE ESTIMATED"
        case nil:
            tableLabel = "TABLE SEARCHING"
        }

        if case .trackingLost(requiresRecalibration: true) = pauseReason {
            instruction = "Recalibration required."
            return
        }
        if pauseReason != nil || phase == .paused {
            instruction = "Tracking paused — hold still."
            return
        }
        switch phase {
        case .findingTable:
            instruction = "Finding a table…"
        case .waitingForHand:
            instruction = "Bring all five fingertips together around the sheep."
        case .formingGrasp:
            instruction = "Hold the five-finger grasp steady."
        case .carrying:
            instruction = isOverPen
                ? "Spread your fingers to release."
                : "Carry the sheep over the fenced pen."
        case .falling:
            instruction = "Let the sheep settle."
        case .success, .complete:
            instruction = "Sheep safely in the pen."
        case .resetting:
            instruction = "Bring all five fingertips together around the sheep."
        case .paused:
            instruction = "Tracking paused — hold still."
        }
    }
}

private final class SheepDropSubscriptionHolder {
    var update: EventSubscription?
}

private enum SheepDropAssetLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

private enum SheepDropDemoStage: Equatable {
    case openNearSpawn
    case formGrasp
    case carryOverPen
    case release
    case settling

    var actionTitle: String? {
        switch self {
        case .openNearSpawn:
            "Open hand near spawn (Demo Mode)"
        case .formGrasp:
            "Form five-finger grasp (Demo Mode)"
        case .carryOverPen:
            "Carry over pen (Demo Mode)"
        case .release:
            "Spread fingers to release (Demo Mode)"
        case .settling:
            nil
        }
    }
}

/// The physical Sheep Drop game rendered in RehabPal's shared mixed space.
/// Hand input is coordinator-owned; the view never starts ARKit or installs a
/// system gesture recognizer.
struct SheepDropView: View {
    let coordinator: RehabSessionCoordinator
    let onProgress: (SessionProgress) -> Void
    let onComplete: (GameplayResult) -> Void

    @State private var game: SheepDropSession
    @State private var demoSource: SyntheticMovementSource
    @State private var worldRoot = Entity()
    @State private var sceneRoot = Entity()
    @State private var sheepBody = Entity()
    @State private var subscriptions = SheepDropSubscriptionHolder()
    @State private var placementState = SheepDropPlacementState()
    @State private var assetLoadState = SheepDropAssetLoadState.loading
    @State private var recalibrationGeneration: Int?
    @State private var lastPausedRevision: Int?
    @State private var completionDelivered = false
    @State private var demoStage = SheepDropDemoStage.openNearSpawn
    @State private var demoTimestamp: TimeInterval = 0

    init(
        request: RehabSessionRequest,
        coordinator: RehabSessionCoordinator,
        onProgress: @escaping (SessionProgress) -> Void,
        onComplete: @escaping (GameplayResult) -> Void
    ) {
        self.coordinator = coordinator
        self.onProgress = onProgress
        self.onComplete = onComplete
        _game = State(initialValue: SheepDropSession(
            affectedHand: request.affectedHand,
            goal: request.goal,
            isSimulated: coordinator.isUsingDemoMode,
            spawnPosition: SheepDropSceneConfiguration.spawnPosition,
            sheepCollisionRadius: SheepDropSceneConfiguration.sheepCollisionRadius
        ))
        _demoSource = State(initialValue: SyntheticMovementSource(hand: request.affectedHand))
    }

    var body: some View {
        RealityView { content, attachments in
            buildSceneRoot()
            if let hud = attachments.entity(for: "sheep-drop-hud") {
                hud.position = [0, 1.14, -0.9]
                worldRoot.addChild(hud)
            }
            content.add(worldRoot)
            subscriptions.update = content.subscribe(to: SceneEvents.Update.self) { event in
                gameStep(deltaTime: event.deltaTime)
            }

            do {
                let visibleSheep = try await Entity(named: "Sheep", in: .main)
                try Task.checkCancellation()
                guard normalizeAndAttach(visibleSheep) else {
                    assetLoadState = .failed("Sheep.usdz has no usable visual bounds.")
                    return
                }
                assetLoadState = .ready
                sceneRoot.isEnabled = placementState.placement != nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                assetLoadState = .failed("Sheep.usdz could not load: \(error.localizedDescription)")
            }
        } update: { content, attachments in
            if let hud = attachments.entity(for: "sheep-drop-hud"),
               hud.parent == nil,
               let root = content.entities.first {
                hud.position = [0, 1.14, -0.9]
                root.addChild(hud)
            }
        } attachments: {
            Attachment(id: "sheep-drop-hud") {
                SheepDropHUD(
                    progress: game.progress,
                    presentation: hudPresentation,
                    loadState: assetLoadState,
                    demoActionTitle: demoStage.actionTitle,
                    onDemoStep: performDemoStep
                )
            }
        }
        .onDisappear {
            subscriptions.update = nil
        }
    }

    private var effectivePhase: SheepDropPhase {
        placementState.placement == nil ? .findingTable : game.phase
    }

    private var hudPresentation: SheepDropHUDPresentation {
        SheepDropHUDPresentation(
            phase: effectivePhase,
            pauseReason: coordinator.pauseReason,
            provenance: coordinator.provenance,
            tableSource: placementState.placement?.source,
            isOverPen: sheepIsOverPen
        )
    }

    private var sheepIsOverPen: Bool {
        let position = sheepBody.position(relativeTo: sceneRoot)
        return abs(position.x) <= SheepDropSession.penInnerHalfExtent &&
            abs(position.z) <= SheepDropSession.penInnerHalfExtent
    }

    private func buildSceneRoot() {
        worldRoot = Entity()
        worldRoot.name = "SheepDropRoot"
        var simulation = PhysicsSimulationComponent()
        simulation.gravity = SheepDropSceneConfiguration.gravity
        worldRoot.components.set(simulation)

        sceneRoot = Entity()
        sceneRoot.name = "SheepDropPlacedScene"
        sceneRoot.isEnabled = false
        worldRoot.addChild(sceneRoot)

        let tableMaterial = SimpleMaterial(
            color: .init(red: 0.46, green: 0.29, blue: 0.16, alpha: 1),
            roughness: 0.85,
            isMetallic: false
        )
        let table = makeStaticBox(
            name: "sheep-drop-table",
            size: SheepDropSceneConfiguration.tableSize,
            material: tableMaterial
        )
        table.position = [0, -SheepDropSceneConfiguration.tableSize.y / 2, 0]
        sceneRoot.addChild(table)

        let grass = ModelEntity(
            mesh: .generateBox(size: [
                SheepDropSceneConfiguration.penSide,
                0.002,
                SheepDropSceneConfiguration.penSide
            ]),
            materials: [SimpleMaterial(
                color: .init(red: 0.24, green: 0.62, blue: 0.24, alpha: 1),
                roughness: 1,
                isMetallic: false
            )]
        )
        grass.name = "sheep-drop-grass"
        grass.position = [0, 0.001, 0]
        sceneRoot.addChild(grass)

        let spawnPad = ModelEntity(
            mesh: .generateBox(size: [
                SheepDropSceneConfiguration.spawnPadSide,
                0.0025,
                SheepDropSceneConfiguration.spawnPadSide
            ]),
            materials: [SimpleMaterial(
                color: .init(red: 0.94, green: 0.72, blue: 0.12, alpha: 1),
                roughness: 0.8,
                isMetallic: false
            )]
        )
        spawnPad.name = "sheep-drop-spawn-pad"
        spawnPad.position = [SheepDropSceneConfiguration.spawnPosition.x, 0.00125, 0]
        sceneRoot.addChild(spawnPad)

        buildFence()
        sheepBody = makeSheepBody()
        sceneRoot.addChild(sheepBody)
        resetSheep(
            position: SheepDropSceneConfiguration.spawnPosition,
            linearVelocity: .zero,
            angularVelocity: .zero
        )
        setSheepMode(.dynamic)
    }

    private func buildFence() {
        let material = SimpleMaterial(
            color: .init(red: 0.56, green: 0.34, blue: 0.14, alpha: 1),
            roughness: 0.9,
            isMetallic: false
        )
        let side = SheepDropSceneConfiguration.penSide
        let thickness = SheepDropSceneConfiguration.fenceThickness
        let height = SheepDropSceneConfiguration.fenceHeight
        let offset = side / 2 - thickness / 2
        let specifications: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([side, height, thickness], [0, height / 2, offset]),
            ([side, height, thickness], [0, height / 2, -offset]),
            ([thickness, height, side], [offset, height / 2, 0]),
            ([thickness, height, side], [-offset, height / 2, 0])
        ]
        for (index, specification) in specifications.enumerated() {
            let wall = makeStaticBox(
                name: "sheep-drop-fence-\(index)",
                size: specification.0,
                material: material
            )
            wall.position = specification.1
            sceneRoot.addChild(wall)
        }
    }

    private func makeStaticBox(
        name: String,
        size: SIMD3<Float>,
        material: SimpleMaterial
    ) -> ModelEntity {
        let shape = ShapeResource.generateBox(size: size)
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        entity.name = name
        entity.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 1,
            material: .generate(
                staticFriction: 0.7,
                dynamicFriction: 0.55,
                restitution: 0.1
            ),
            mode: .static
        ))
        entity.components.set(CollisionComponent(shapes: [shape]))
        return entity
    }

    private func makeSheepBody() -> Entity {
        let entity = Entity()
        entity.name = "sheep-drop-fitted-collision-root"
        entity.position = SheepDropSceneConfiguration.spawnPosition
        let shape = ShapeResource.generateSphere(
            radius: SheepDropSceneConfiguration.sheepCollisionRadius
        )
        var body = PhysicsBodyComponent(
            shapes: [shape],
            mass: 0.15,
            material: .generate(
                staticFriction: 0.7,
                dynamicFriction: 0.55,
                restitution: 0.1
            ),
            mode: .dynamic
        )
        body.linearDamping = 1.2
        body.angularDamping = 1.2
        entity.components.set(body)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(PhysicsMotionComponent())
        return entity
    }

    private func normalizeAndAttach(_ visibleSheep: Entity) -> Bool {
        let bounds = visibleSheep.visualBounds(relativeTo: visibleSheep)
        let halfDiagonal = simd_length(bounds.extents) / 2
        guard halfDiagonal.isFinite, halfDiagonal > .ulpOfOne,
              bounds.center.x.isFinite, bounds.center.y.isFinite,
              bounds.center.z.isFinite else {
            return false
        }
        let scale = SheepDropSceneConfiguration.sheepVisibleRadius / halfDiagonal
        visibleSheep.name = "SheepVisible"
        visibleSheep.scale = SIMD3<Float>(repeating: scale)
        visibleSheep.position = -bounds.center * scale
        sheepBody.addChild(visibleSheep)
        return true
    }

    private func gameStep(deltaTime: TimeInterval) {
        coordinator.updateRequiredJoints(SheepDropSession.requiredJoints)
        refreshPlacement()
        if coordinator.isUsingDemoMode {
            demoTimestamp += max(0, deltaTime)
        }
        if processRecalibrationIfNeeded() {
            return
        }

        guard case let .active(request, _, _) = coordinator.phase,
              request.experience == .exercise(.sheepDrop) else {
            pauseForCoordinatorStateIfNeeded()
            return
        }
        lastPausedRevision = nil
        guard assetLoadState == .ready,
              let placement = placementState.placement,
              let coordinates = SheepDropCoordinateSpace(
                tableTransform: placement.transform
              ) else {
            freezeSheep(at: sheepBody.position(relativeTo: sceneRoot))
            return
        }

        let timestamp = coordinator.isUsingDemoMode
            ? demoTimestamp
            : ProcessInfo.processInfo.systemUptime
        let frame = coordinator.isUsingDemoMode
            ? demoSource.latestJointFrame
            : coordinates.penLocalFrame(coordinator.currentFrame)
        handle(game.process(
            frame: frame,
            observation: observation(in: coordinates),
            at: timestamp
        ), coordinates: coordinates)
    }

    private func refreshPlacement() {
        if let placement = coordinator.currentTablePlacement {
            placementState.receive(placement)
        }
        guard let placement = placementState.placement else {
            sceneRoot.isEnabled = false
            return
        }
        if !placementState.isLocked {
            sceneRoot.setTransformMatrix(placement.transform, relativeTo: nil)
        }
        sceneRoot.isEnabled = assetLoadState == .ready
    }

    private func processRecalibrationIfNeeded() -> Bool {
        if let generation = coordinator.pendingProcessorResetGeneration,
           recalibrationGeneration != generation {
            let update = game.pause(requiresRecalibration: true)
            apply(update.command, coordinates: currentCoordinateSpace)
            recalibrationGeneration = generation
            _ = coordinator.acknowledgeProcessorReset(generation)
        }

        guard let generation = recalibrationGeneration else { return false }
        guard case .trackingLost(requiresRecalibration: true) = coordinator.pauseReason else {
            recalibrationGeneration = nil
            return false
        }
        freezeSheep(at: sheepBody.position(relativeTo: sceneRoot))
        if let frame = coordinator.currentFrame {
            _ = coordinator.acknowledgeProcessorCalibration(
                generation: generation,
                frameTimestamp: frame.timestamp
            )
        }
        return true
    }

    private func pauseForCoordinatorStateIfNeeded() {
        guard lastPausedRevision != coordinator.phaseRevision else {
            freezeSheep(at: sheepBody.position(relativeTo: sceneRoot))
            return
        }
        let requiresRecalibration: Bool
        if case .trackingLost(requiresRecalibration: true) = coordinator.pauseReason {
            requiresRecalibration = true
        } else {
            requiresRecalibration = false
        }
        apply(
            game.pause(requiresRecalibration: requiresRecalibration).command,
            coordinates: currentCoordinateSpace
        )
        lastPausedRevision = coordinator.phaseRevision
    }

    private var currentCoordinateSpace: SheepDropCoordinateSpace? {
        placementState.placement.flatMap {
            SheepDropCoordinateSpace(tableTransform: $0.transform)
        }
    }

    private func observation(
        in coordinates: SheepDropCoordinateSpace
    ) -> SheepDropObservation {
        let position = sheepBody.position(relativeTo: sceneRoot)
        let worldVelocity = sheepBody.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
        let velocity = coordinates.penLocalVelocity(fromWorld: worldVelocity)
        let offsetFromSpawn = position - SheepDropSceneConfiguration.spawnPosition
        let onSpawn = abs(offsetFromSpawn.x) <= SheepDropSceneConfiguration.spawnPadSide / 2 &&
            abs(offsetFromSpawn.z) <= SheepDropSceneConfiguration.spawnPadSide / 2 &&
            position.y >= SheepDropSceneConfiguration.floorY &&
            position.y <= SheepDropSceneConfiguration.sheepCollisionRadius * 1.5 &&
            simd_length(velocity) <= SheepDropSession.maximumSettledSpeed
        let outside = abs(position.x) > SheepDropSceneConfiguration.safeHorizontalRadius ||
            abs(position.z) > SheepDropSceneConfiguration.safeHorizontalRadius ||
            position.y < SheepDropSceneConfiguration.safeMinimumY ||
            position.y > SheepDropSceneConfiguration.safeMaximumY
        return SheepDropObservation(
            position: position,
            velocity: velocity,
            isRestingOnSpawnSurface: onSpawn,
            isOutsideSafeVolume: outside
        )
    }

    private func handle(
        _ update: SheepDropUpdate,
        coordinates: SheepDropCoordinateSpace?
    ) {
        onProgress(game.progress)
        apply(update.command, coordinates: coordinates)

        switch update.event {
        case .pickupBegan:
            placementState.lockAtFirstPickup()
        case .waitingForHand, .formingGrasp:
            if update.command == .none {
                setSheepMode(.dynamic)
            }
        case .falling:
            if update.command == .none {
                setSheepMode(.dynamic)
            }
        case .resetAfterSuccess, .failedDropReset:
            prepareNextDemoAttempt()
        case let .complete(result):
            guard !completionDelivered else { return }
            completionDelivered = true
            onComplete(result)
        case .carrying, .released, .placementSucceeded,
             .successWaiting, .trackingPaused:
            break
        }
    }

    private func apply(
        _ command: SheepDropCommand,
        coordinates: SheepDropCoordinateSpace?
    ) {
        switch command {
        case .none:
            break
        case let .pickup(position), let .carry(position):
            setSheepMode(.kinematic)
            setMotion(linearVelocity: .zero, angularVelocity: .zero)
            sheepBody.setPosition(position, relativeTo: sceneRoot)
        case .release:
            setMotion(linearVelocity: .zero, angularVelocity: .zero)
            setSheepMode(.dynamic)
        case let .freeze(position):
            freezeSheep(at: position)
        case let .reset(position, linearVelocity, angularVelocity):
            let worldLinear = coordinates?.worldVelocity(fromPenLocal: linearVelocity)
                ?? linearVelocity
            let worldAngular = coordinates?.worldVelocity(fromPenLocal: angularVelocity)
                ?? angularVelocity
            resetSheep(
                position: position,
                linearVelocity: worldLinear,
                angularVelocity: worldAngular
            )
        }
    }

    private func freezeSheep(at position: SIMD3<Float>) {
        setSheepMode(.kinematic)
        sheepBody.setPosition(position, relativeTo: sceneRoot)
        setMotion(linearVelocity: .zero, angularVelocity: .zero)
    }

    private func resetSheep(
        position: SIMD3<Float>,
        linearVelocity: SIMD3<Float>,
        angularVelocity: SIMD3<Float>
    ) {
        setSheepMode(.kinematic)
        sheepBody.setPosition(position, relativeTo: sceneRoot)
        setMotion(linearVelocity: linearVelocity, angularVelocity: angularVelocity)
    }

    private func setSheepMode(_ mode: PhysicsBodyMode) {
        guard var body = sheepBody.components[PhysicsBodyComponent.self] else { return }
        body.mode = mode
        sheepBody.components.set(body)
    }

    private func setMotion(
        linearVelocity: SIMD3<Float>,
        angularVelocity: SIMD3<Float>
    ) {
        var motion = sheepBody.components[PhysicsMotionComponent.self]
            ?? PhysicsMotionComponent()
        motion.linearVelocity = linearVelocity
        motion.angularVelocity = angularVelocity
        sheepBody.components.set(motion)
    }

    private func performDemoStep() {
        guard coordinator.isUsingDemoMode,
              assetLoadState == .ready,
              let coordinates = currentCoordinateSpace,
              game.phase != .complete else {
            return
        }
        switch demoStage {
        case .openNearSpawn:
            processDemoPose(
                .open,
                centeredAt: SheepDropSceneConfiguration.spawnPosition,
                coordinates: coordinates
            )
            demoStage = .formGrasp
        case .formGrasp:
            let center = sheepBody.position(relativeTo: sceneRoot)
            processDemoPose(.clustered, centeredAt: center, coordinates: coordinates)
            demoTimestamp += SheepDropSession.pickupDwellDuration
            processDemoPose(.clustered, centeredAt: center, coordinates: coordinates)
            demoStage = .carryOverPen
        case .carryOverPen:
            demoTimestamp += 0.35
            processDemoPose(
                .clustered,
                centeredAt: [0, 0.22, 0],
                coordinates: coordinates
            )
            demoStage = .release
        case .release:
            processDemoPose(.open, centeredAt: [0, 0.22, 0], coordinates: coordinates)
            demoTimestamp += SheepDropSession.releaseDwellDuration
            processDemoPose(.open, centeredAt: [0, 0.22, 0], coordinates: coordinates)
            demoStage = .settling
        case .settling:
            break
        }
    }

    private func processDemoPose(
        _ pose: SyntheticSheepDropPose,
        centeredAt center: SIMD3<Float>,
        coordinates: SheepDropCoordinateSpace
    ) {
        demoSource.setSheepDropPose(pose, centeredAt: center, at: demoTimestamp)
        handle(game.process(
            frame: demoSource.latestJointFrame,
            observation: observation(in: coordinates),
            at: demoTimestamp
        ), coordinates: coordinates)
    }

    private func prepareNextDemoAttempt() {
        guard coordinator.isUsingDemoMode else { return }
        demoStage = .openNearSpawn
        demoSource.setSheepDropPose(
            .open,
            centeredAt: SheepDropSceneConfiguration.spawnPosition,
            at: demoTimestamp
        )
    }
}

private struct SheepDropHUD: View {
    let progress: SessionProgress
    let presentation: SheepDropHUDPresentation
    let loadState: SheepDropAssetLoadState
    let demoActionTitle: String?
    let onDemoStep: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            SessionProgressLabel(progress: progress)
            HStack(spacing: 12) {
                Text(presentation.provenanceLabel)
                    .foregroundStyle(
                        presentation.provenanceLabel.contains("SIMULATED")
                            ? Color.orange
                            : Color.green
                    )
                Text(presentation.tableLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.bold())

            Text(presentation.instruction)
                .font(.headline)
                .multilineTextAlignment(.center)

            switch loadState {
            case .loading:
                ProgressView("Loading sheep…")
            case .ready:
                EmptyView()
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if let demoActionTitle, progress.completed < progress.goal {
                Button(demoActionTitle, action: onDemoStep)
                    .buttonStyle(.borderedProminent)
            }
            Text("Pickup infers an all-five-fingertip pose; it does not measure grip force.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(width: 440)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
