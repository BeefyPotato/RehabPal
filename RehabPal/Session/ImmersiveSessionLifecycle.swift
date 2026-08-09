import Foundation
import Observation

@MainActor
@Observable
final class ImmersiveSessionLifecycle {
    enum State: Equatable {
        case closed
        case opening(UUID)
        case open
    }

    enum OpeningCompletion: Equatable {
        case accepted
        case dismissStaleOpen
    }

    private(set) var state: State = .closed

    func beginOpening() -> UUID? {
        guard state == .closed else { return nil }
        let attempt = UUID()
        state = .opening(attempt)
        return attempt
    }

    func completeOpening(_ attempt: UUID) -> OpeningCompletion {
        guard state == .opening(attempt) else {
            return .dismissStaleOpen
        }
        state = .open
        return .accepted
    }

    @discardableResult
    func failOpening(_ attempt: UUID) -> Bool {
        guard state == .opening(attempt) else { return false }
        state = .closed
        return true
    }

    /// Invalidates an in-flight open as well as closing an opened space.
    /// Returning true tells the caller to issue a dismiss action.
    func close() -> Bool {
        guard state != .closed else { return false }
        state = .closed
        return true
    }
}
