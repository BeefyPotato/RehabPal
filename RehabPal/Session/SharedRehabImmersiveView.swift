import RealityKit
import SwiftUI

/// The single mixed-space host shared by all joint-tracked experiences.
/// Feature tasks add their focused RealityKit content beneath this root.
struct SharedRehabImmersiveView: View {
    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "RehabSessionRoot"
            content.add(root)
        }
    }
}
