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
                let buddy = ModelEntity(
                    mesh: .generateSphere(radius: 0.11),
                    materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)]
                )
                buddy.name = "primitive-squeeze-buddy"
                content.add(buddy)
            } update: { content in
                guard let buddy = content.entities.first else { return }
                let squish = max(0.7, 1 - closure * 0.25)
                buddy.scale = [1 + closure * 0.15, squish, 1 + closure * 0.15]
            }
            .frame(height: 280)

            Text(trackingVisible ? cue : "Hands temporarily not visible")
                .font(.title2.weight(.semibold))
            ProgressView(value: Double(completedRepetitions), total: Double(prescribedRepetitions))
                .frame(maxWidth: 360)
            Text("Vision tracking observes closing and release—not grip force.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var cue: String {
        switch phase {
        case .open: "Close around the stress ball"
        case .closing: "Hold gently"
        case .reopening: "Open your hand"
        }
    }
}
