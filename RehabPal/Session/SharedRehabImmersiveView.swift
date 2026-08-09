import RealityKit
import SwiftUI

enum SharedRehabImmersiveRoute: Equatable, Sendable {
    case balance
    case squeeze
    case sheepDrop
    case wristAssessment
    case handAssessment
    case empty

    static func resolve(_ request: RehabSessionRequest?) -> Self {
        guard let request else { return .empty }
        switch request.experience {
        case .exercise(.balance):
            return .balance
        case .exercise(.squeeze):
            return .squeeze
        case .exercise(.sheepDrop):
            return .sheepDrop
        case .wristAssessment:
            return .wristAssessment
        case .handAssessment:
            return .handAssessment
        }
    }
}

/// The single mixed-space host shared by all joint-tracked experiences.
struct SharedRehabImmersiveView: View {
    let session: RehabSessionCoordinator

    var body: some View {
        Group {
            switch SharedRehabImmersiveRoute.resolve(session.activeRequest) {
            case .balance:
                if let request = session.activeRequest {
                    BalancePlatformView(
                        request: request,
                        coordinator: session,
                        onProgress: session.accept,
                        onComplete: finishBalance
                    )
                }
            case .squeeze:
                if let request = session.activeRequest {
                    SqueezeBuddyView(
                        request: request,
                        coordinator: session,
                        closeThreshold: session.squeezeCloseThreshold,
                        reopenThreshold: session.squeezeReopenThreshold,
                        holdSeconds: session.squeezeHoldSeconds,
                        onProgress: session.accept,
                        onComplete: finishSqueeze
                    )
                }
            case .sheepDrop:
                if let request = session.activeRequest {
                    SheepDropView(
                        request: request,
                        coordinator: session,
                        onProgress: session.accept,
                        onComplete: finishSheepDrop
                    )
                }
            case .wristAssessment:
                if let request = session.activeRequest {
                    WristDiagnosticImmersiveView(
                        request: request,
                        coordinator: session,
                        onProgress: session.accept,
                        onComplete: finishWristAssessment
                    )
                }
            case .handAssessment:
                if let request = session.activeRequest {
                    FingerDiagnosticImmersiveView(
                        request: request,
                        coordinator: session,
                        onProgress: session.accept,
                        onComplete: finishHandAssessment
                    )
                }
            case .empty:
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

    private func finishSheepDrop(_ result: GameplayResult) {
        _ = session.finish(with: .gameplay(result))
    }

    private func finishWristAssessment(_ result: AssessmentResult.WristResult) -> Bool {
        session.finish(with: .wristAssessment(result)) != nil
    }

    private func finishHandAssessment(_ result: [HandDigit: DigitROMSummary]) -> Bool {
        session.finish(with: .handAssessment(result)) != nil
    }
}
