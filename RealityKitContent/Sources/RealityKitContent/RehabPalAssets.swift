import RealityKit

public enum RehabPalAssets {
    @MainActor
    public static func loadPet(named name: String = "PlaceholderPet") async -> Entity {
        if let entity = try? await Entity(named: name, in: .module) {
            entity.name = "placeholder-pet-asset"
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
        return root
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
