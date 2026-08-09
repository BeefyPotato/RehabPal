import SwiftUI

struct ContentView: View {
    @State private var state: AppState
    @State private var selectedExercise: ExerciseKind?
    @State private var handTracking: HandTrackingEngine
    @State private var session: RehabSessionCoordinator
    @State private var showingSettings = false
    @State private var immersiveSpaceIsOpen = false

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    init() {
        let state = AppState()
        let tracking = HandTrackingEngine()
        _state = State(initialValue: state)
        _handTracking = State(initialValue: tracking)
        _session = State(initialValue: RehabSessionCoordinator(
            prescription: state.prescription,
            liveTracking: tracking
        ))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch DemoRouter.screen(for: state) {
                case .home:
                    HomeView(state: state)
                case .medication:
                    MedicationGateView(state: state)
                case .routine:
                    if let selectedExercise {
                        ExerciseDemoView(
                            exercise: selectedExercise,
                            prescription: state.prescription,
                            useDemoFallback: session.isUsingDemoMode,
                            liveObservation: handTracking.latestObservation
                        ) { result in
                            complete(.gameplay(result))
                            self.selectedExercise = nil
                        } onCancel: {
                            self.selectedExercise = nil
                        }
                    } else {
                        DailyRoutineView(state: state) { selectedExercise = $0 }
                    }
                case .wristAssessment:
                    WristAssessmentView(
                        useDemoFallback: session.isUsingDemoMode
                    ) { result in
                        complete(.wristAssessment(result))
                    }
                case .handAssessment:
                    HandROMAssessmentView(
                        useDemoFallback: session.isUsingDemoMode,
                        liveObservation: handTracking.latestObservation
                    ) { result in
                        complete(.handAssessment(result))
                    }
                case .symptoms:
                    SymptomCheckView(state: state)
                case .report:
                    AfterCareReportView(state: state)
                case .petReward:
                    PetRewardView(state: state)
                case .complete:
                    FullForTodayView(state: state)
                }
            }
            .animation(.easeInOut, value: state.stage)

            Button {
                showingSettings = true
            } label: {
                Label("Demo settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .padding(24)

            sessionLifecycleOverlay
        }
        .sheet(isPresented: $showingSettings) {
            DemoSettingsView(state: state)
        }
        .task(id: currentRequest) {
            await transition(to: currentRequest)
        }
        .task(id: session.activeRequest) {
            await monitorJointFrames()
        }
        .onDisappear {
            session.cancel()
        }
    }

    @ViewBuilder
    private var sessionLifecycleOverlay: some View {
        switch session.phase {
        case .starting:
            SessionLifecycleCard {
                ProgressView()
                Text("Starting live hand tracking…")
                    .font(.headline)
            }
        case let .failed(failure) where failure.request == currentRequest:
            SessionLifecycleCard {
                Text("Live tracking didn’t start")
                    .font(.title2.bold())
                Text(failureMessage(failure.reason))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack {
                    if failure.recoveryActions.contains(.retryLive) {
                        Button("Retry") {
                            Task { await retryLive() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if failure.recoveryActions.contains(.enterDemoMode) {
                        Button("Use Demo Mode") {
                            Task { await enterDemoMode() }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Cancel") {
                        cancelCurrentExperience()
                    }
                    .buttonStyle(.borderless)
                }
                Text("Demo Mode uses simulated movement and labels its results.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case let .paused(_, progress, .trackingLost(requiresRecalibration)):
            SessionLifecycleCard {
                Text(requiresRecalibration ? "Recalibration required" : "Tracking paused")
                    .font(.title2.bold())
                Text("Completed \(progress.completed) of \(progress.goal) is preserved. The partial movement was discarded.")
                    .multilineTextAlignment(.center)
                if requiresRecalibration {
                    Button("Recalibrate") {
                        _ = session.confirmRecalibration()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Keep your prescribed hand in view to continue.")
                        .foregroundStyle(.secondary)
                }
            }
        default:
            EmptyView()
        }
    }

    private var currentRequest: RehabSessionRequest? {
        switch DemoRouter.screen(for: state) {
        case .routine:
            guard let selectedExercise else { return nil }
            return RehabSessionRequest(
                experience: .exercise(selectedExercise),
                prescription: state.prescription,
                goal: selectedExercise == .balance ? 8 : state.prescription.squeezeRepetitions
            )
        case .wristAssessment:
            return RehabSessionRequest(
                experience: .wristAssessment,
                prescription: state.prescription,
                goal: state.prescription.assessmentAttemptsPerDirection * WristDirection.allCases.count + state.prescription.assessmentAttemptsPerDirection
            )
        case .handAssessment:
            return RehabSessionRequest(
                experience: .handAssessment,
                prescription: state.prescription,
                goal: HandDigit.allCases.count * 2
            )
        default:
            return nil
        }
    }

    private func transition(to request: RehabSessionRequest?) async {
        guard let request else {
            await closeImmersiveSession()
            return
        }
        if session.activeRequest != request {
            await closeImmersiveSession()
        }
        await session.startLive(request)
        guard session.provenance == .live else { return }
        await presentImmersiveSpace()
    }

    private func retryLive() async {
        await session.retryLive()
        guard session.provenance == .live else { return }
        await presentImmersiveSpace()
    }

    private func enterDemoMode() async {
        guard session.startDemoMode() else { return }
        await presentImmersiveSpace()
    }

    private func presentImmersiveSpace() async {
        guard !immersiveSpaceIsOpen else { return }
        switch await openImmersiveSpace(id: RehabSessionCoordinator.immersiveSpaceID) {
        case .opened:
            immersiveSpaceIsOpen = true
        case .userCancelled:
            session.failImmersiveSpace("Opening the immersive session was cancelled.")
        case .error:
            session.failImmersiveSpace("The immersive session could not be opened.")
        @unknown default:
            session.failImmersiveSpace("The immersive session could not be opened.")
        }
    }

    private func closeImmersiveSession() async {
        session.cancel()
        if immersiveSpaceIsOpen {
            await dismissImmersiveSpace()
            immersiveSpaceIsOpen = false
        }
    }

    private func monitorJointFrames() async {
        while !Task.isCancelled, session.activeRequest != nil {
            if session.provenance == .live || session.pauseReason != nil {
                session.receiveJointFrame(
                    handTracking.latestJointFrame,
                    at: ProcessInfo.processInfo.systemUptime
                )
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func complete(_ payload: SessionOutcomePayload) {
        guard let progress = session.progress else { return }
        session.accept(SessionProgress(
            completed: progress.goal,
            goal: progress.goal,
            partial: 0
        ))
        guard let outcome = session.finish(with: payload) else { return }
        _ = state.route(outcome)
    }

    private func cancelCurrentExperience() {
        session.cancel()
        if case .routine = DemoRouter.screen(for: state) {
            selectedExercise = nil
        }
    }

    private func failureMessage(_ reason: SessionFailure.Reason) -> String {
        switch reason {
        case let .affectedHandMismatch(expected, _):
            "This session requires the prescribed \(expected.rawValue) hand."
        case .invalidGoal:
            "The prescribed goal is invalid."
        case .liveTrackingUnavailable:
            "Hand tracking is unavailable on this device."
        case let .liveStartupFailed(message), let .immersiveSpaceFailed(message):
            message
        }
    }
}

private struct SessionLifecycleCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .padding(28)
        .frame(maxWidth: 520)
        .glassBackgroundEffect()
        .padding(40)
    }
}

#Preview {
    ContentView()
}
