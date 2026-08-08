import RealityKit
import RealityKitContent
import SwiftUI

struct PetRewardView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 24) {
            RealityView { content in
                content.add(RehabPalAssets.makePrimitivePet())
            }
            .frame(width: 320, height: 300)
            Text("Your Recovery Pet earned a treat")
                .font(.largeTitle.bold())
            Button("Feed treat") { _ = state.feedPet() }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
        }
        .padding(50)
    }
}
