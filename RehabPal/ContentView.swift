import SwiftUI

struct ContentView: View {
    @State private var state: AppState
    @State private var selectedExercise: ExerciseKind?
    @State private var exerciseStarted = false
    @State private var handTracking: HandTrackingEngine
    @State private var session: RehabSessionCoordinator
    @State private var immersiveLifecycle = ImmersiveSessionLifecycle()
    @State private var showingSettings = false

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    init(
        state: AppState,
        handTracking: HandTrackingEngine,
        session: RehabSessionCoordinator
    ) {
        _state = State(initialValue: state)
        _handTracking = State(initialValue: handTracking)
        _session = State(initialValue: session)
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
                            onBegin: { exerciseStarted = true }
                        ) {
                            self.selectedExercise = nil
                            exerciseStarted = false
                        }
                    } else {
                        DailyRoutineView(state: state) { exercise in
                            selectedExercise = exercise
                            exerciseStarted = Self.beginsRoutineExerciseImmediately(exercise)
                        }
                    }
                case .wristAssessment:
                    WristAssessmentView(
                        prescription: state.prescription,
                        useDemoFallback: session.isUsingDemoMode
                    )
                case .handAssessment:
                    HandROMAssessmentView(
                        prescription: state.prescription,
                        useDemoFallback: session.isUsingDemoMode
                    )
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
        .task(id: session.monitoringGeneration) {
            await monitorJointFrames()
        }
        .onChange(of: session.phase) { _, phase in
            if case let .completed(outcome) = phase,
               state.route(outcome) {
                if case .exercise = outcome.request.experience {
                    selectedExercise = nil
                    exerciseStarted = false
                }
            }
            if case .failed = phase {
                state.cancelActiveSession()
                Task { await dismissImmersiveAfterFailure() }
            }
        }
        .onDisappear {
            Task { await closeImmersiveSession() }
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
                    .disabled(!session.canConfirmRecalibration)
                    if !session.canConfirmRecalibration {
                        Text("Hold the prompted pose until recalibration is ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            return Self.routineExerciseRequest(
                for: selectedExercise,
                hasBegun: exerciseStarted,
                prescription: state.prescription
            )
        case .wristAssessment:
            return state.prescription.sessionRequest(for: .wristAssessment)
        case .handAssessment:
            return state.prescription.sessionRequest(for: .handAssessment)
        default:
            return nil
        }
    }

    static func routineExerciseRequest(
        for exercise: ExerciseKind?,
        hasBegun: Bool,
        prescription: Prescription
    ) -> RehabSessionRequest? {
        guard let exercise else { return nil }
        guard hasBegun || beginsRoutineExerciseImmediately(exercise) else { return nil }
        return prescription.sessionRequest(for: .exercise(exercise))
    }

    static func beginsRoutineExerciseImmediately(_ exercise: ExerciseKind) -> Bool {
        switch exercise {
        case .balance:
            true
        case .squeeze, .sheepDrop:
            false
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
        let launched = await RehabSessionLaunchSequence.startLive(
            request: request,
            coordinator: session,
            lifecycle: immersiveLifecycle,
            open: openRehabImmersiveSpace,
            dismiss: dismissImmersiveSpace.callAsFunction
        )
        guard launched, activateAuthorizedSession() else {
            if launched {
                await closeImmersiveSession()
            }
            return
        }
    }

    private func retryLive() async {
        guard case let .failed(failure) = session.phase else { return }
        let launched = await RehabSessionLaunchSequence.startLive(
            request: failure.request,
            coordinator: session,
            lifecycle: immersiveLifecycle,
            open: openRehabImmersiveSpace,
            dismiss: dismissImmersiveSpace.callAsFunction
        )
        guard launched, activateAuthorizedSession() else {
            if launched {
                await closeImmersiveSession()
            }
            return
        }
    }

    private func enterDemoMode() async {
        let launched = await RehabSessionLaunchSequence.startDemo(
            coordinator: session,
            lifecycle: immersiveLifecycle,
            open: openRehabImmersiveSpace,
            dismiss: dismissImmersiveSpace.callAsFunction
        )
        guard launched, activateAuthorizedSession() else {
            if launched {
                await closeImmersiveSession()
            }
            return
        }
    }

    private func activateAuthorizedSession() -> Bool {
        guard let authorization = session.authorization,
              state.activateSession(
                  authorization.request,
                  provenance: authorization.provenance
              ) else {
            return false
        }
        return true
    }

    private func openRehabImmersiveSpace() async -> RehabImmersiveOpenResult {
        switch await openImmersiveSpace(id: RehabSessionCoordinator.immersiveSpaceID) {
        case .opened:
            return .opened
        case .userCancelled:
            return .userCancelled
        case .error:
            return .failed("The immersive session could not be opened.")
        @unknown default:
            return .failed("The immersive session could not be opened.")
        }
    }

    private func closeImmersiveSession() async {
        state.cancelActiveSession()
        session.cancel()
        if immersiveLifecycle.close() {
            await dismissImmersiveSpace()
        }
    }

    private func monitorJointFrames() async {
        while !Task.isCancelled, session.shouldMonitorFrames {
            if session.provenance == .live || session.pauseReason != nil {
                session.pollLiveTracking(at: ProcessInfo.processInfo.systemUptime)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func dismissImmersiveAfterFailure() async {
        guard immersiveLifecycle.close() else { return }
        await dismissImmersiveSpace()
    }

    private func cancelCurrentExperience() {
        session.cancel()
        state.cancelActiveSession()
        switch DemoRouter.screen(for: state) {
        case .routine:
            selectedExercise = nil
            exerciseStarted = false
        case .wristAssessment, .handAssessment:
            _ = state.cancelSessionAndReturnToRoutine()
        default:
            break
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
        case .liveAuthorizationDenied:
            "Hand-tracking authorization was denied."
        case let .liveProviderFailed(message),
             let .liveStartupFailed(message),
             let .immersiveSpaceFailed(message):
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
    let state = AppState()
    let tracking = HandTrackingEngine()
    ContentView(
        state: state,
        handTracking: tracking,
        session: RehabSessionCoordinator(
            prescription: state.prescription,
            liveTracking: tracking
        )
    )
}
