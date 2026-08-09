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
        case ignoreStaleOpen
    }

    private(set) var state: State = .closed
    private var ownerAttempt: UUID?

    func beginOpening() -> UUID? {
        guard state == .closed else { return nil }
        let attempt = UUID()
        ownerAttempt = attempt
        state = .opening(attempt)
        return attempt
    }

    func completeOpening(_ attempt: UUID) -> OpeningCompletion {
        guard ownerAttempt == attempt, state == .opening(attempt) else {
            return state == .closed ? .dismissStaleOpen : .ignoreStaleOpen
        }
        state = .open
        return .accepted
    }

    @discardableResult
    func failOpening(_ attempt: UUID) -> Bool {
        guard ownerAttempt == attempt, state == .opening(attempt) else { return false }
        ownerAttempt = nil
        state = .closed
        return true
    }

    /// Closes only when `attempt` still owns the currently opened space. This
    /// prevents a stale async completion from dismissing a newer launch.
    @discardableResult
    func close(_ attempt: UUID) -> Bool {
        guard ownerAttempt == attempt, state != .closed else { return false }
        ownerAttempt = nil
        state = .closed
        return true
    }

    /// Invalidates an in-flight open as well as closing an opened space.
    /// Returning true tells the caller to issue a dismiss action.
    func close() -> Bool {
        guard state != .closed else { return false }
        ownerAttempt = nil
        state = .closed
        return true
    }
}
