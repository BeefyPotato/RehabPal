import Foundation
import RealityKit

enum ImportedModelLoader {
    @MainActor
    static func loadModel(named name: String = "model", maximumDimension: Float = 0.28, playAnimations: Bool = true) async -> Entity {
        if let entity = try? await Entity(named: name) {
            prepare(entity, maximumDimension: maximumDimension, playAnimations: playAnimations)
            return entity
        }

        if let url = Bundle.main.url(forResource: name, withExtension: "usdc", subdirectory: "3dAssets/model"),
           let entity = try? await Entity(contentsOf: url) {
            prepare(entity, maximumDimension: maximumDimension, playAnimations: playAnimations)
            return entity
        }

        return makeFallbackModel(maximumDimension: maximumDimension)
    }

    @MainActor
    static func makeTreat() -> Entity {
        let root = Entity()
        root.name = "primitive-treat"
        let treat = ModelEntity(
            mesh: .generateBox(width: 0.065, height: 0.025, depth: 0.035, cornerRadius: 0.012),
            materials: [SimpleMaterial(color: .systemBrown, isMetallic: false)]
        )
        root.addChild(treat)
        return root
    }

    @MainActor
    private static func prepare(_ entity: Entity, maximumDimension: Float, playAnimations: Bool) {
        entity.name = "imported-model"
        normalize(entity, maximumDimension: maximumDimension)
        if playAnimations {
            playDefaultAnimations(on: entity)
        }
    }

    @MainActor
    private static func normalize(_ entity: Entity, maximumDimension: Float) {
        var bounds = entity.visualBounds(relativeTo: entity)
        let largest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        guard largest.isFinite, largest > 0.0001 else { return }
        let factor = min(1, maximumDimension / largest)
        entity.scale *= SIMD3<Float>(repeating: factor)
        bounds = entity.visualBounds(relativeTo: entity.parent)
        entity.position += [-bounds.center.x, -bounds.min.y, -bounds.center.z]
    }

    @MainActor
    private static func playDefaultAnimations(on entity: Entity) {
        for animation in entity.availableAnimations {
            entity.playAnimation(animation.repeat(), transitionDuration: 0.2, startsPaused: false)
        }

        for child in entity.children {
            playDefaultAnimations(on: child)
        }
    }

    @MainActor
    private static func makeFallbackModel(maximumDimension: Float) -> Entity {
        let root = Entity()
        root.name = "primitive-model-fallback"
        let body = ModelEntity(
            mesh: .generateSphere(radius: maximumDimension / 2),
            materials: [SimpleMaterial(color: .systemMint, isMetallic: false)]
        )
        root.addChild(body)
        return root
    }
}
