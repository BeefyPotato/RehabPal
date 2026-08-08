import RealityKit
import SwiftUI

struct BalancePlatformView: View {
    let direction: WristDirection?
    let progress: Double
    let trackingVisible: Bool

    var body: some View {
        VStack(spacing: 18) {
            RealityView { content in
                let root = Entity()
                let platform = ModelEntity(
                    mesh: .generateBox(width: 0.55, height: 0.025, depth: 0.4, cornerRadius: 0.025),
                    materials: [SimpleMaterial(color: .systemTeal, isMetallic: false)]
                )
                let target = ModelEntity(
                    mesh: .generateCylinder(height: 0.006, radius: 0.07),
                    materials: [SimpleMaterial(color: .systemGreen.withAlphaComponent(0.7), isMetallic: false)]
                )
                target.position.y = 0.018
                let ball = ModelEntity(
                    mesh: .generateSphere(radius: 0.035),
                    materials: [SimpleMaterial(color: .white, isMetallic: true)]
                )
                ball.position = [0, 0.065, 0]
                root.addChild(platform)
                root.addChild(target)
                root.addChild(ball)
                content.add(root)
            }
            .frame(height: 280)

            Text(trackingVisible ? "Move \(direction?.rawValue ?? "to centre")" : "Hands temporarily not visible")
                .font(.title2.weight(.semibold))
            ProgressView(value: progress)
                .frame(maxWidth: 360)
        }
        .accessibilityElement(children: .contain)
    }
}
