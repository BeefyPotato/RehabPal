import RealityKit
import SwiftUI

struct DiagnosticCompletionDelivery: Sendable {
    private(set) var isFinished = false

    mutating func attempt(_ delivery: () -> Bool) {
        guard !isFinished else { return }
        isFinished = delivery()
    }
}

private final class WristDiagnosticSubscriptionHolder {
    var update: EventSubscription?
}

private final class FingerDiagnosticSubscriptionHolder {
    var update: EventSubscription?
}

struct WristDiagnosticImmersiveView: View {
    let coordinator: RehabSessionCoordinator
    let onProgress: (SessionProgress) -> Void
    let onComplete: (AssessmentResult.WristResult) -> Bool
    private let configurationError: String?

    @State private var processor: WristDiagnosticProcessor
    @State private var subscriptions = WristDiagnosticSubscriptionHolder()
    @State private var phaseLabel = "Neutral calibration"
    @State private var demoTimestamp: TimeInterval = 0
    @State private var completionDelivery = DiagnosticCompletionDelivery()
    @State private var recalibrationGeneration: Int?

    init(
        request: RehabSessionRequest,
        coordinator: RehabSessionCoordinator,
        onProgress: @escaping (SessionProgress) -> Void,
        onComplete: @escaping (AssessmentResult.WristResult) -> Bool
    ) {
        self.coordinator = coordinator
        self.onProgress = onProgress
        self.onComplete = onComplete
        let attempts = request.diagnosticAttemptsPerSubject
        configurationError = attempts == nil
            ? "The wrist diagnostic goal is invalid. Close this session and retry."
            : nil
        _processor = State(initialValue: WristDiagnosticProcessor(
            affectedHand: request.affectedHand,
            attemptsPerTarget: attempts ?? 1,
            isSimulated: coordinator.isUsingDemoMode,
            configuration: coordinator.wristDiagnosticPrescription
        ))
    }

    var body: some View {
        if let configurationError {
            DiagnosticConfigurationErrorView(message: configurationError)
        } else {
            RealityView { content, attachments in
                let root = Entity()
                root.name = "WristDiagnosticRoot"
                if let hud = attachments.entity(for: "wrist-diagnostic-hud") {
                    hud.position = [0, 1.15, -0.8]
                    root.addChild(hud)
                }
                content.add(root)
                subscriptions.update = content.subscribe(to: SceneEvents.Update.self) { _ in
                    processLiveFrame()
                }
            } update: { content, attachments in
                if let hud = attachments.entity(for: "wrist-diagnostic-hud"),
                   hud.parent == nil,
                   let root = content.entities.first {
                    hud.position = [0, 1.15, -0.8]
                    root.addChild(hud)
                }
            } attachments: {
                Attachment(id: "wrist-diagnostic-hud") {
                    DiagnosticHUD(
                        presentation: DiagnosticHUDPresentation(
                            progress: processor.progress,
                            subject: processor.currentTarget?.title ?? "Wrist assessment",
                            phase: phaseLabel,
                            isDemo: coordinator.isUsingDemoMode
                        ),
                        trackingConfidence: Double(processor.trackingConfidence),
                        isPaused: coordinator.pauseReason != nil,
                        demoActionTitle: processor.isCalibrated
                            ? "Complete attempt (Demo Mode)"
                            : "Calibrate neutral (Demo Mode)",
                        onDemoStep: performDemoStep
                    )
                }
            }
        }
    }

    private func processLiveFrame() {
        coordinator.updateRequiredJoints(WristNeutralCalibration.requiredJoints)
        guard coordinator.activeRequest?.experience == .wristAssessment else {
            processor.pause(requiresRecalibration: false)
            return
        }
        guard !coordinator.isUsingDemoMode else {
            return
        }
        if processRecalibrationIfNeeded() {
            return
        }
        for observation in coordinator.consumeDiagnosticObservations() {
            handle(processor.process(observation: observation))
        }
        if case .paused = coordinator.phase {
            processor.pause(requiresRecalibration: false)
        }
    }

    private func processRecalibrationIfNeeded() -> Bool {
        if let generation = coordinator.pendingProcessorResetGeneration,
           recalibrationGeneration != generation {
            processor.pause(requiresRecalibration: true)
            recalibrationGeneration = generation
            _ = coordinator.acknowledgeProcessorReset(generation)
        }

        guard let generation = recalibrationGeneration else { return false }
        guard case .trackingLost(requiresRecalibration: true) = coordinator.pauseReason else {
            recalibrationGeneration = nil
            return false
        }

        if !processor.isCalibrated {
            let observations = coordinator.consumeDiagnosticObservations()
            for observation in observations {
                handle(processor.process(observation: observation))
                if processor.isCalibrated { break }
            }
            if observations.isEmpty, let frame = coordinator.currentFrame {
                handle(processor.process(frame: frame))
            }
        }
        if processor.isCalibrated, let frame = coordinator.currentFrame {
            _ = coordinator.acknowledgeProcessorCalibration(
                generation: generation,
                frameTimestamp: frame.timestamp
            )
        }
        return true
    }

    private func handle(_ event: WristDiagnosticEvent) {
        switch event {
        case .waitingForCalibration:
            phaseLabel = "Hold the prescribed hand neutral with four level knuckles"
        case let .ready(target, _, _):
            phaseLabel = target == .center
                ? "Hold neutral"
                : "Move to the \(processor.configuration.targetDegrees.formatted())° target"
        case let .holding(_, elapsed, _, _):
            phaseLabel = "Hold steady \(elapsed.formatted(.number.precision(.fractionLength(1)))) / \(processor.configuration.holdSeconds.formatted()) s"
        case .returnToNeutral:
            phaseLabel = "Return to neutral within \(processor.configuration.neutralReturnToleranceDegrees.formatted())°"
        case .attemptCompleted:
            phaseLabel = "Next attempt"
            onProgress(processor.progress)
        case let .completed(result):
            onProgress(processor.progress)
            completionDelivery.attempt {
                onComplete(result)
            }
        case .paused:
            phaseLabel = "Tracking paused"
        }
    }

    private func performDemoStep() {
        guard coordinator.isUsingDemoMode, !processor.isComplete else { return }
        if !processor.isCalibrated {
            handle(processor.process(frame: demoWristFrame(
                target: .center,
                at: demoTimestamp
            )))
            return
        }
        guard let target = processor.currentTarget else { return }
        let holdStartedAt = demoTimestamp + 0.1
        let holdSteps = Int(ceil(processor.configuration.holdSeconds / 0.1))
        for step in 0...holdSteps {
            handle(processor.process(frame: demoWristFrame(
                target: target,
                at: holdStartedAt + Double(step) / 10
            )))
        }
        demoTimestamp = holdStartedAt + processor.configuration.holdSeconds
        demoTimestamp += 0.1
        handle(processor.process(frame: demoWristFrame(target: .center, at: demoTimestamp)))
    }

    private func demoWristFrame(
        target: WristAssessmentTarget,
        at timestamp: TimeInterval
    ) -> HandJointFrame {
        let degrees = processor.configuration.targetDegrees * .pi / 180
        let pitch: Float
        let roll: Float
        switch target {
        case .center: (pitch, roll) = (0, 0)
        case .forward: (pitch, roll) = (degrees, 0)
        case .backward: (pitch, roll) = (-degrees, 0)
        case .left: (pitch, roll) = (0, -degrees)
        case .right: (pitch, roll) = (0, degrees)
        }
        let transform = MovementMath.wristTransform(pitch: pitch, roll: roll)
        return .synthetic(
            hand: processor.affectedHand,
            timestamp: timestamp,
            joints: Dictionary(uniqueKeysWithValues: WristNeutralCalibration.requiredJoints.map {
                ($0, HandJointSample.tracked(transform: transform))
            })
        )
    }
}

struct FingerDiagnosticImmersiveView: View {
    let coordinator: RehabSessionCoordinator
    let onProgress: (SessionProgress) -> Void
    let onComplete: ([HandDigit: DigitROMSummary]) -> Bool
    private let configurationError: String?

    @State private var processor: FingerROMDiagnosticProcessor
    @State private var subscriptions = FingerDiagnosticSubscriptionHolder()
    @State private var phaseLabel: String
    @State private var demoTimestamp: TimeInterval = 0
    @State private var completionDelivery = DiagnosticCompletionDelivery()
    @State private var recalibrationGeneration: Int?

    init(
        request: RehabSessionRequest,
        coordinator: RehabSessionCoordinator,
        onProgress: @escaping (SessionProgress) -> Void,
        onComplete: @escaping ([HandDigit: DigitROMSummary]) -> Bool
    ) {
        self.coordinator = coordinator
        self.onProgress = onProgress
        self.onComplete = onComplete
        let attempts = request.diagnosticAttemptsPerSubject
        configurationError = attempts == nil
            ? "The finger diagnostic goal is invalid. Close this session and retry."
            : nil
        _phaseLabel = State(initialValue: "Stabilize extension for \(coordinator.fingerDiagnosticPrescription.extensionStabilitySeconds.formatted()) seconds")
        _processor = State(initialValue: FingerROMDiagnosticProcessor(
            affectedHand: request.affectedHand,
            attemptsPerDigit: attempts ?? 1,
            isSimulated: coordinator.isUsingDemoMode,
            configuration: coordinator.fingerDiagnosticPrescription
        ))
    }

    var body: some View {
        if let configurationError {
            DiagnosticConfigurationErrorView(message: configurationError)
        } else {
            RealityView { content, attachments in
                let root = Entity()
                root.name = "FingerDiagnosticRoot"
                if let hud = attachments.entity(for: "finger-diagnostic-hud") {
                    hud.position = [0, 1.15, -0.8]
                    root.addChild(hud)
                }
                content.add(root)
                subscriptions.update = content.subscribe(to: SceneEvents.Update.self) { _ in
                    processLiveFrame()
                }
            } update: { content, attachments in
                if let hud = attachments.entity(for: "finger-diagnostic-hud"),
                   hud.parent == nil,
                   let root = content.entities.first {
                    hud.position = [0, 1.15, -0.8]
                    root.addChild(hud)
                }
            } attachments: {
                Attachment(id: "finger-diagnostic-hud") {
                    DiagnosticHUD(
                        presentation: DiagnosticHUDPresentation(
                            progress: processor.progress,
                            subject: processor.currentDigit?.title ?? "Finger ROM",
                            phase: phaseLabel,
                            isDemo: coordinator.isUsingDemoMode
                        ),
                        trackingConfidence: processor.trackingConfidence,
                        isPaused: coordinator.pauseReason != nil,
                        demoActionTitle: "Complete ROM attempt (Demo Mode)",
                        onDemoStep: performDemoStep
                    )
                }
            }
        }
    }

    private func processLiveFrame() {
        if let digit = processor.currentDigit {
            coordinator.updateRequiredJoints(Set(
                FingerROMMetrics.requiredJoints(for: digit)
            ))
        }
        guard coordinator.activeRequest?.experience == .handAssessment else {
            processor.pause()
            return
        }
        guard !coordinator.isUsingDemoMode else {
            return
        }
        if processRecalibrationIfNeeded() {
            return
        }
        for observation in coordinator.consumeDiagnosticObservations() {
            handle(processor.process(observation: observation))
        }
        if case .paused = coordinator.phase {
            processor.pause()
        }
    }

    private func processRecalibrationIfNeeded() -> Bool {
        if let generation = coordinator.pendingProcessorResetGeneration,
           recalibrationGeneration != generation {
            processor.pause()
            recalibrationGeneration = generation
            _ = coordinator.acknowledgeProcessorReset(generation)
        }

        guard let generation = recalibrationGeneration else { return false }
        guard case .trackingLost(requiresRecalibration: true) = coordinator.pauseReason else {
            recalibrationGeneration = nil
            return false
        }

        if !processor.isCalibrated {
            let observations = coordinator.consumeDiagnosticObservations()
            for observation in observations {
                handle(processor.process(observation: observation))
                if processor.isCalibrated { break }
            }
            if observations.isEmpty, let frame = coordinator.currentFrame {
                handle(processor.process(frame: frame))
            }
        }
        if processor.isCalibrated, let frame = coordinator.currentFrame {
            _ = coordinator.acknowledgeProcessorCalibration(
                generation: generation,
                frameTimestamp: frame.timestamp
            )
        }
        return true
    }

    private func handle(_ event: FingerDiagnosticEvent) {
        switch event {
        case .stabilizingExtension:
            phaseLabel = "Stabilize extension for \(processor.configuration.extensionStabilitySeconds.formatted()) seconds"
        case .capturingMotion:
            phaseLabel = processor.currentDigit == .thumb
                ? "Oppose thumb by \((processor.configuration.thumbOppositionReduction * 100).formatted())% toward little finger"
                : "Flex through at least \(processor.configuration.minimumTotalExcursionDegrees.formatted())° total excursion"
        case .returningToExtension:
            phaseLabel = processor.currentDigit == .thumb
                ? "Return thumb within \((processor.configuration.thumbOppositionReturnTolerance * 100).formatted())% of baseline"
                : "Return within \(processor.configuration.extensionReturnToleranceDegrees.formatted())° of extension"
        case .attemptCompleted:
            phaseLabel = "Next attempt"
            onProgress(processor.progress)
        case let .completed(result):
            onProgress(processor.progress)
            completionDelivery.attempt {
                onComplete(result)
            }
        case .paused:
            phaseLabel = "Tracking paused"
        }
    }

    private func performDemoStep() {
        guard coordinator.isUsingDemoMode,
              !processor.isComplete,
              let digit = processor.currentDigit else {
            return
        }
        let baselineOpposition: Float? = digit == .thumb ? 0.08 : nil
        let extensionStartedAt = demoTimestamp
        let extensionSteps = Int(ceil(processor.configuration.extensionStabilitySeconds / 0.1))
        for step in 0...extensionSteps {
            handle(processor.process(sample: demoSample(
                digit: digit,
                flexion: .zero,
                opposition: baselineOpposition,
                at: extensionStartedAt + Double(step) / 10
            )))
        }
        demoTimestamp = extensionStartedAt + processor.configuration.extensionStabilitySeconds
        demoTimestamp += 0.1
        handle(processor.process(sample: demoSample(
            digit: digit,
            flexion: [processor.configuration.minimumTotalExcursionDegrees + 5, 10, 5],
            opposition: digit == .thumb
                ? 0.08 * max(0, 1 - processor.configuration.thumbOppositionReduction - 0.05)
                : nil,
            at: demoTimestamp
        )))
        demoTimestamp += 0.1
        handle(processor.process(sample: demoSample(
            digit: digit,
            flexion: .zero,
            opposition: baselineOpposition,
            at: demoTimestamp
        )))
        demoTimestamp += 0.1
    }

    private func demoSample(
        digit: HandDigit,
        flexion: SIMD3<Float>,
        opposition: Float?,
        at timestamp: TimeInterval
    ) -> FingerDiagnosticSample {
        FingerDiagnosticSample(
            hand: processor.affectedHand,
            timestamp: timestamp,
            digit: digit,
            metrics: FingerROMMetrics(
                interiorAngles: SIMD3<Float>(repeating: 180) - flexion,
                oppositionDistance: opposition
            )
        )
    }
}

private struct DiagnosticConfigurationErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Diagnostic unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}
