import RealityKit
import SwiftUI

struct BalancePlatformView: View {
    let target: BalanceTarget
    let ballPosition: SIMD2<Float>
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
                let targetEntity = ModelEntity(
                    mesh: .generateCylinder(height: 0.008, radius: 0.055),
                    materials: [SimpleMaterial(color: .black.withAlphaComponent(0.72), isMetallic: false)]
                )
                targetEntity.name = "moving-hole"
                targetEntity.position = [target.x, 0.017, target.z]
                let ball = ModelEntity(
                    mesh: .generateSphere(radius: 0.035),
                    materials: [SimpleMaterial(color: .white, isMetallic: true)]
                )
                ball.position = [0, 0.065, 0]
                ball.name = "guided-ball"
                root.addChild(platform)
                root.addChild(targetEntity)
                root.addChild(ball)
                content.add(root)
            } update: { content in
                guard let root = content.entities.first else { return }
                root.findEntity(named: "moving-hole")?.position = [target.x, 0.017, target.z]
                root.findEntity(named: "guided-ball")?.position = [ballPosition.x, 0.065, ballPosition.y]
            }
            .frame(height: 280)

            Text(trackingVisible ? "Guide the ball into the glowing hole" : "Tracking paused — hold your hand in view")
                .font(.title2.weight(.semibold))
            ProgressView(value: progress)
                .frame(maxWidth: 360)
        }
        .accessibilityElement(children: .contain)
    }
}
