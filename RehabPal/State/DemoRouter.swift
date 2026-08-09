enum DemoScreen: Equatable {
    case home
    case medication
    case routine
    case wristAssessment
    case handAssessment
    case symptoms
    case report
    case petReward
    case complete
}

enum DemoRouter {
    @MainActor
    static func screen(for state: AppState) -> DemoScreen {
        switch state.stage {
        case .home: .home
        case .medicationGate: .medication
        case .routine: .routine
        case .wristAssessment: .wristAssessment
        case .handAssessment: .handAssessment
        case .symptomCheck: .symptoms
        case .report: .report
        case .petReward: .petReward
        case .complete: .complete
        }
    }
}
