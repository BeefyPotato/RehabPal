import Observation

@MainActor
@Observable
final class AppState {
    enum Stage: Equatable {
        case home
    }

    private(set) var stage: Stage = .home
}
