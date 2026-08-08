import RealityKit

public enum RehabPalAssets {
    @MainActor
    public static func makePlaceholderScene() -> Entity {
        let root = Entity()
        root.name = "placeholder-pet"

        let preview = ModelEntity(mesh: .generateSphere(radius: 0.08))
        preview.position.y = 0.08
        root.addChild(preview)

        return root
    }
}
