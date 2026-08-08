import RealityKit

public enum RehabPalAssets {
    @MainActor
    public static func makePrimitivePet() -> Entity {
        let root = Entity()
        root.name = "placeholder-pet"
        let body = ModelEntity(mesh: .generateSphere(radius: 0.08))
        body.position.y = 0.08
        root.addChild(body)
        return root
    }
}
