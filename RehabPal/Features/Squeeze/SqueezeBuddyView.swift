import RealityKit
import SwiftUI

struct SqueezeBuddyView: View {
    let closure: Float
    let phase: SqueezeRepDetector.Phase
    let completedRepetitions: Int
    let prescribedRepetitions: Int
    let trackingVisible: Bool

    var body: some View {
        VStack(spacing: 18) {
            RealityView { content in
                let root = Entity()
                let buddy = ModelEntity(
                    mesh: .generateSphere(radius: 0.11),
                    materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)]
                )
                buddy.name = "primitive-squeeze-buddy"
                let eyeMaterial = SimpleMaterial(color: .black, isMetallic: false)
                for x: Float in [-0.035, 0.035] {
                    let eye = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [eyeMaterial])
                    eye.position = [x, 0.025, 0.102]
                    root.addChild(eye)
                }
                root.addChild(buddy)
                content.add(root)
            } update: { content in
                guard let buddy = content.entities.first?.findEntity(named: "primitive-squeeze-buddy") else { return }
                let squish = max(0.7, 1 - closure * 0.25)
                buddy.scale = [1 + closure * 0.15, squish, 1 + closure * 0.15]
            }
            .frame(height: 280)

            HStack(spacing: 8) {
                phaseStep("Close", active: phase == .closing)
                Image(systemName: "chevron.right")
                phaseStep("Hold", active: phase == .closing && closure > 0.7)
                Image(systemName: "chevron.right")
                phaseStep("Open", active: phase == .reopening)
            }

            Text(trackingVisible ? cue : "Hands temporarily not visible")
                .font(.title2.weight(.semibold))
            ProgressView(value: Double(completedRepetitions), total: Double(prescribedRepetitions))
                .frame(maxWidth: 360)
            Text("Vision tracking observes closing and release—not grip force.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func phaseStep(_ title: String, active: Bool) -> some View {
        Text(title).font(.headline).padding(.horizontal, 16).padding(.vertical, 8)
            .background(active ? Color.orange : Color.secondary.opacity(0.18), in: Capsule())
    }

    private var cue: String {
        switch phase {
        case .open: "Close around the stress ball"
        case .closing: "Hold gently"
        case .reopening: "Open your hand"
        }
    }
}
