import RealityKit
import RealityKitContent
import SwiftUI

struct PetRewardView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 24) {
            RealityView { content in
                let pet = await RehabPalAssets.loadPet()
                let treat = await RehabPalAssets.loadTreat()
                treat.position = [0.13, 0.025, 0.04]
                content.add(pet)
                content.add(treat)
            }
            .frame(width: 320, height: 300)
            Text("Your Recovery Pet earned a treat")
                .font(.largeTitle.bold())
            Text("Feeding this treat restores 20% fullness.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Feed treat") { _ = state.feedPet() }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
        }
        .padding(50)
    }
}
