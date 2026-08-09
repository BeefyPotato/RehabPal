import Foundation

enum RehabImmersiveOpenResult: Equatable, Sendable {
    case opened
    case userCancelled
    case failed(String)
}

/// Orders the injected immersive and ARKit boundaries. The sequence owns no UI
/// state, which keeps delayed-open and delayed-start races deterministic in
/// tests while `ImmersiveSessionLifecycle` owns the actual space generation.
@MainActor
enum RehabSessionLaunchSequence {
    static func startLive(
        request: RehabSessionRequest,
        coordinator: RehabSessionCoordinator,
        lifecycle: ImmersiveSessionLifecycle,
        open: @escaping @MainActor () async -> RehabImmersiveOpenResult,
        dismiss: @escaping @MainActor () async -> Void
    ) async -> Bool {
        guard let openingAttempt = lifecycle.beginOpening() else { return false }
        guard let startToken = coordinator.prepareLiveStart(request) else {
            _ = lifecycle.failOpening(openingAttempt)
            return false
        }

        let openResult = await open()
        if Task.isCancelled {
            let stillOwnsOpening = lifecycle.failOpening(openingAttempt)
            coordinator.cancelPreparedLive(startToken)
            if stillOwnsOpening, openResult == .opened {
                await dismiss()
            }
            return false
        }

        switch openResult {
        case .opened:
            switch lifecycle.completeOpening(openingAttempt) {
            case .accepted:
                let started = await coordinator.startPreparedLive(startToken)
                guard started, !Task.isCancelled else {
                    if lifecycle.close(openingAttempt) {
                        await dismiss()
                    }
                    return false
                }
                return true
            case .dismissStaleOpen:
                coordinator.cancelPreparedLive(startToken)
                await dismiss()
                return false
            case .ignoreStaleOpen:
                coordinator.cancelPreparedLive(startToken)
                return false
            }
        case .userCancelled:
            if lifecycle.failOpening(openingAttempt) {
                coordinator.failImmersiveSpace(
                    "Opening the immersive session was cancelled."
                )
            } else {
                coordinator.cancelPreparedLive(startToken)
            }
            return false
        case let .failed(message):
            if lifecycle.failOpening(openingAttempt) {
                coordinator.failImmersiveSpace(message)
            } else {
                coordinator.cancelPreparedLive(startToken)
            }
            return false
        }
    }

    static func startDemo(
        coordinator: RehabSessionCoordinator,
        lifecycle: ImmersiveSessionLifecycle,
        open: @escaping @MainActor () async -> RehabImmersiveOpenResult,
        dismiss: @escaping @MainActor () async -> Void
    ) async -> Bool {
        guard let openingAttempt = lifecycle.beginOpening() else { return false }
        guard let demoToken = coordinator.prepareDemoStart() else {
            _ = lifecycle.failOpening(openingAttempt)
            return false
        }
        let openResult = await open()

        if Task.isCancelled {
            let stillOwnsOpening = lifecycle.failOpening(openingAttempt)
            coordinator.cancelPreparedDemo(demoToken)
            if stillOwnsOpening, openResult == .opened {
                await dismiss()
            }
            return false
        }

        switch openResult {
        case .opened:
            switch lifecycle.completeOpening(openingAttempt) {
            case .accepted:
                guard coordinator.completePreparedDemo(demoToken) else {
                    if lifecycle.close(openingAttempt) {
                        await dismiss()
                    }
                    return false
                }
                return true
            case .dismissStaleOpen:
                coordinator.cancelPreparedDemo(demoToken)
                await dismiss()
                return false
            case .ignoreStaleOpen:
                coordinator.cancelPreparedDemo(demoToken)
                return false
            }
        case .userCancelled:
            if lifecycle.failOpening(openingAttempt) {
                coordinator.failPreparedDemoOpen(
                    demoToken,
                    message: "Opening the immersive session was cancelled."
                )
            } else {
                coordinator.cancelPreparedDemo(demoToken)
            }
            return false
        case let .failed(message):
            if lifecycle.failOpening(openingAttempt) {
                coordinator.failPreparedDemoOpen(demoToken, message: message)
            } else {
                coordinator.cancelPreparedDemo(demoToken)
            }
            return false
        }
    }
}
