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

    static func isOutsideSafeVolume(_ position: SIMD3<Float>) -> Bool {
        simd_length(SIMD2<Float>(position.x, position.z)) > safeHorizontalRadius ||
            position.y < safeMinimumY ||
            position.y > safeMaximumY
    }
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
            joints: localJoints,
            anchorTransform: frame.anchorTransform.map { worldToTable * $0 }
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

enum SheepDropPlacementUpdate: Equatable, Sendable {
    case unchanged
    case acquired
    case invalidated
}

struct SheepDropPlacementState: Equatable, Sendable {
    private(set) var placement: TablePlacement?
    private(set) var isLocked = false

    var isPlacementAvailable: Bool {
        placement != nil
    }

    @discardableResult
    mutating func receive(_ placement: TablePlacement?) -> SheepDropPlacementUpdate {
        guard !isLocked else { return .unchanged }
        let previous = self.placement
        guard previous != placement else { return .unchanged }
        self.placement = placement
        if previous != nil {
            return .invalidated
        }
        return placement == nil ? .unchanged : .acquired
    }

    mutating func lockAtFirstPickup() {
        guard placement != nil else { return }
        isLocked = true
    }
}

struct SheepDropInputChronology: Equatable, Sendable {
    private(set) var lastConsumedTimestamp: TimeInterval?

    mutating func consume(_ frame: HandJointFrame?) -> HandJointFrame? {
        guard let frame,
              frame.timestamp.isFinite,
              lastConsumedTimestamp.map({ frame.timestamp > $0 }) ?? true else {
            return nil
        }
        lastConsumedTimestamp = frame.timestamp
        return frame
    }
}

private extension SheepDropPhase {
    var requiresFreshHandObservation: Bool {
        switch self {
        case .findingTable, .waitingForHand, .formingGrasp, .carrying, .paused:
            true
        case .falling, .success, .resetting, .complete:
            false
        }
    }
}

enum SheepDropAsset {
    /// The CC0 USDZ declares Z-up and the model faces source -Y. RealityKit is
    /// Y-up; after standing it upright, yaw it so its head points from the
    /// positive-X spawn pad toward the pen at the origin.
    static let sourceToPenOrientation =
        simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]) *
        simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

    @MainActor
    static func makeVisibleModel(from importedScene: Entity) -> Entity? {
        guard let sheepHierarchy = importedScene.findEntity(named: "RootNode") else {
            return nil
        }
        sheepHierarchy.removeFromParent()
        sheepHierarchy.orientation = sourceToPenOrientation

        let visibleSheep = Entity()
        visibleSheep.name = "SheepVisible"
        visibleSheep.addChild(sheepHierarchy)

        let bounds = sheepHierarchy.visualBounds(relativeTo: visibleSheep)
        let halfDiagonal = simd_length(bounds.extents) / 2
        guard halfDiagonal.isFinite, halfDiagonal > .ulpOfOne,
              bounds.center.x.isFinite, bounds.center.y.isFinite,
              bounds.center.z.isFinite else {
            return nil
        }

        let scale = SheepDropSceneConfiguration.sheepVisibleRadius / halfDiagonal
        sheepHierarchy.scale = SIMD3<Float>(repeating: scale)
        let scaledBottom = (bounds.center.y - bounds.extents.y / 2) * scale
        sheepHierarchy.position = [
            -bounds.center.x * scale,
            -SheepDropSceneConfiguration.sheepCollisionRadius - scaledBottom,
            -bounds.center.z * scale
        ]
        return visibleSheep
    }
}

struct SheepDropHUDPresentation: Equatable, Sendable {
    let provenanceLabel: String
    let tableLabel: String
    let instruction: String
    let demoActionTitle: String?

    init(
        phase: SheepDropPhase,
        pauseReason: SessionPauseReason?,
        provenance: SessionProvenance?,
        tableSource: TablePlacement.Source?,
        isOverPen: Bool,
        requestedDemoActionTitle: String? = nil
    ) {
        demoActionTitle = provenance == .demo ? requestedDemoActionTitle : nil
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
            instruction = "Pinch and drag the sheep."
        case .formingGrasp:
            instruction = "Keep dragging the sheep."
        case .carrying:
            instruction = isOverPen
                ? "Spread your fingers to release."
                : "Carry the sheep over the fenced pen."
        case .falling:
            instruction = "Let the sheep settle."
        case .success, .complete:
            instruction = "Sheep safely in the pen."
        case .resetting:
            instruction = "Pinch and drag the sheep."
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
/// Live manipulation follows test 9-3's system-targeted drag gesture. The
/// coordinator still owns global wrist presence and the session lifecycle.
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
    @State private var inputChronology = SheepDropInputChronology()

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
                let importedScene = try await Entity(named: "Sheep", in: .main)
                try Task.checkCancellation()
                guard let visibleSheep = SheepDropAsset.makeVisibleModel(
                    from: importedScene
                ) else {
                    assetLoadState = .failed("Sheep.usdz has no usable visual bounds.")
                    return
                }
                sheepBody.addChild(visibleSheep)
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
                let recovery = ImmersiveRecoveryPresentation.make(
                    phase: coordinator.phase,
                    canConfirmRecalibration: coordinator.canConfirmRecalibration
                )
                ImmersiveRecoveryStack(
                    presentation: recovery,
                    onRecalibrate: { _ = coordinator.confirmRecalibration() },
                    onBackToRoutine: coordinator.requestReturnToRoutine
                ) {
                    SheepDropHUD(
                        progress: game.progress,
                        presentation: hudPresentation,
                        loadState: assetLoadState,
                        isRecovering: recovery != nil,
                        assistedActionEnabled: AssistedProgressControl.isAuthorized(
                            coordinator.phase,
                            for: .exercise(.sheepDrop)
                        ) && assetLoadState == .ready,
                        onAssistedStep: performAssistedStep
                    )
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged(handleDirectDragChanged)
                .onEnded(handleDirectDragEnded)
        )
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
            isOverPen: sheepIsOverPen,
            requestedDemoActionTitle: demoStage.actionTitle
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
        entity.components.set(InputTargetComponent())
        entity.components.set(PhysicsMotionComponent())
        return entity
    }

    private func gameStep(deltaTime: TimeInterval) {
        coordinator.updateRequiredJoints(coordinator.isUsingDemoMode ? SheepDropSession.requiredJoints : [.wrist])
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
            discardPickupDwellIfNeeded()
            freezeSheep(at: sheepBody.position(relativeTo: sceneRoot))
            return
        }

        if !coordinator.isUsingDemoMode, game.phase == .paused {
            handle(game.resumeAfterTrackingInterruption(), coordinates: coordinates)
        }

        // Live pickup/carry/release is entirely driven by the targeted drag.
        // Physics settlement continues ticking without hand-joint samples.
        if !coordinator.isUsingDemoMode,
           game.phase != .falling,
           game.phase != .success,
           game.phase != .resetting {
            return
        }
        let retainedFrame = coordinator.isUsingDemoMode ? demoSource.latestJointFrame : nil
        let frame: HandJointFrame?
        let timestamp: TimeInterval
        if game.phase.requiresFreshHandObservation {
            guard let freshFrame = inputChronology.consume(retainedFrame) else {
                return
            }
            frame = freshFrame
            timestamp = freshFrame.timestamp
        } else {
            frame = nil
            timestamp = coordinator.isUsingDemoMode
                ? demoTimestamp
                : ProcessInfo.processInfo.systemUptime
        }
        handle(game.process(
            frame: frame,
            observation: observation(in: coordinates),
            at: timestamp
        ), coordinates: coordinates)
    }

    private func handleDirectDragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        guard !coordinator.isUsingDemoMode,
              value.entity === sheepBody,
              case let .active(request, _, _) = coordinator.phase,
              request.experience == .exercise(.sheepDrop),
              let coordinates = currentCoordinateSpace else { return }
        let world = value.convert(value.location3D, from: .local, to: .scene)
        let position = coordinates.penLocalPosition(fromWorld: world)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let update = game.phase == .carrying
            ? game.updateDirectDrag(to: position, timestamp: timestamp)
            : game.beginDirectDrag(at: position, timestamp: timestamp)
        handle(update, coordinates: coordinates)
    }

    private func handleDirectDragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        guard !coordinator.isUsingDemoMode,
              value.entity === sheepBody,
              case let .active(request, _, _) = coordinator.phase,
              request.experience == .exercise(.sheepDrop),
              let coordinates = currentCoordinateSpace else { return }
        handle(
            game.endDirectDrag(timestamp: ProcessInfo.processInfo.systemUptime),
            coordinates: coordinates
        )
    }

    private func refreshPlacement() {
        let update = placementState.receive(coordinator.currentTablePlacement)
        if update == .invalidated {
            discardPickupDwellIfNeeded()
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

    private func discardPickupDwellIfNeeded() {
        guard game.phase == .formingGrasp else { return }
        handle(
            game.pause(requiresRecalibration: false),
            coordinates: currentCoordinateSpace
        )
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
        let outside = SheepDropSceneConfiguration.isOutsideSafeVolume(position)
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

    private func performAssistedStep() {
        guard AssistedProgressControl.isAuthorized(
            coordinator.phase,
            for: .exercise(.sheepDrop)
        ), assetLoadState == .ready else { return }
        let before = game.completedDrops
        guard SheepDropAssistedProgressAction.process(
            session: &game,
            nextTimestamp: &demoTimestamp
        ) else { return }
        _ = coordinator.registerAssistedProgress(from: before, to: game.completedDrops)
        onProgress(game.progress)
        if game.phase == .complete, let result = game.result {
            onComplete(result)
        } else {
            resetSheep(
                position: SheepDropSceneConfiguration.spawnPosition,
                linearVelocity: .zero,
                angularVelocity: .zero
            )
        }
    }

    private func processDemoPose(
        _ pose: SyntheticSheepDropPose,
        centeredAt center: SIMD3<Float>,
        coordinates: SheepDropCoordinateSpace
    ) {
        demoSource.setSheepDropPose(pose, centeredAt: center, at: demoTimestamp)
        guard let frame = inputChronology.consume(demoSource.latestJointFrame) else {
            return
        }
        handle(game.process(
            frame: frame,
            observation: observation(in: coordinates),
            at: frame.timestamp
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
    let isRecovering: Bool
    let assistedActionEnabled: Bool
    let onAssistedStep: () -> Void

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

            if !isRecovering {
                Text(presentation.instruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

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

            if progress.completed < progress.goal {
                Button("Complete Sheep Placement (Assisted)", action: onAssistedStep)
                    .buttonStyle(.borderedProminent)
                    .disabled(!assistedActionEnabled)
                Text("ASSISTED — NOT TRACKED")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            Text("Use the system pinch to drag the sheep; open your hand to release.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(width: 440)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
