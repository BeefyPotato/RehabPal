import RealityKit
import RealityKitContent
import SwiftUI

struct ContentView: View {
    var body: some View {
        RealityView { content in
            content.add(RehabPalAssets.makePlaceholderScene())
        }
        .overlay(alignment: .bottom) {
            Text("RehabPal")
                .font(.title)
                .padding()
        }
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
}
