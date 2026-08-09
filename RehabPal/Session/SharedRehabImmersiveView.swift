import RealityKit
import SwiftUI

/// The single mixed-space host shared by all joint-tracked experiences.
struct SharedRehabImmersiveView: View {
    let session: RehabSessionCoordinator

    var body: some View {
        Group {
            if let request = session.activeRequest,
               request.experience == .exercise(.balance) {
                BalancePlatformView(
                    request: request,
                    coordinator: session,
                    onProgress: session.accept,
                    onComplete: finishBalance
                )
            } else if let request = session.activeRequest,
                      request.experience == .exercise(.squeeze) {
                SqueezeBuddyView(
                    request: request,
                    coordinator: session,
                    closeThreshold: session.squeezeCloseThreshold,
                    reopenThreshold: session.squeezeReopenThreshold,
                    holdSeconds: session.squeezeHoldSeconds,
                    onProgress: session.accept,
                    onComplete: finishSqueeze
                )
            } else {
                RealityView { content in
                    let root = Entity()
                    root.name = "RehabSessionRoot"
                    content.add(root)
                }
            }
        }
    }

    private func finishBalance(_ result: GameplayResult) {
        _ = session.finish(with: .gameplay(result))
    }

    private func finishSqueeze(_ result: GameplayResult) {
        _ = session.finish(with: .gameplay(result))
    }
}
