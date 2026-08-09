import RealityKit

public enum RehabPalAssets {
    @MainActor
    public static func loadPet(named name: String = "PlaceholderPet") async -> Entity {
        if let entity = try? await Entity(named: name, in: .module) {
            entity.name = "placeholder-pet-asset"
            normalize(entity, maximumDimension: 0.22)
            return entity
        }
        return makePrimitivePet()
    }

    @MainActor
    public static func loadTreat(named name: String = "PlaceholderTreat") async -> Entity {
        if let entity = try? await Entity(named: name, in: .module) {
            entity.name = "placeholder-treat-asset"
            return entity
        }
        return makePrimitiveTreat()
    }

    @MainActor
    public static func makePrimitivePet() -> Entity {
        let root = Entity()
        root.name = "primitive-pet-fallback"

        let body = ModelEntity(
            mesh: .generateSphere(radius: 0.08),
            materials: [SimpleMaterial(color: .systemMint, isMetallic: false)]
        )
        body.position.y = 0.08
        let head = ModelEntity(
            mesh: .generateSphere(radius: 0.055),
            materials: [SimpleMaterial(color: .systemMint, isMetallic: false)]
        )
        head.position = [0, 0.17, 0.025]
        root.addChild(body)
        root.addChild(head)
        normalize(root, maximumDimension: 0.22)
        return root
    }

    @MainActor
    public static func normalize(_ entity: Entity, maximumDimension: Float) {
        var bounds = entity.visualBounds(relativeTo: entity)
        let largest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        guard largest.isFinite, largest > 0.0001 else { return }
        let factor = min(1, maximumDimension / largest)
        entity.scale *= SIMD3<Float>(repeating: factor)
        bounds = entity.visualBounds(relativeTo: entity.parent)
        entity.position += [-bounds.center.x, -bounds.min.y, -bounds.center.z]
    }

    @MainActor
    public static func makePrimitiveTreat() -> Entity {
        let root = Entity()
        root.name = "primitive-treat-fallback"
        let treat = ModelEntity(
            mesh: .generateBox(width: 0.065, height: 0.025, depth: 0.035, cornerRadius: 0.012),
            materials: [SimpleMaterial(color: .systemBrown, isMetallic: false)]
        )
        root.addChild(treat)
        return root
    }
}
