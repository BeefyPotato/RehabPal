import Foundation
import simd

struct SqueezeHandMetrics: Equatable, Sendable {
    static let fingerTipJoints: [HandJoint] = [
        .thumbTip, .indexFingerTip, .middleFingerTip, .ringFingerTip, .littleFingerTip
    ]
    static let palmJoints: [HandJoint] = [
        .indexFingerMetacarpal,
        .middleFingerMetacarpal,
        .ringFingerMetacarpal,
        .littleFingerMetacarpal
    ]
    static let flexionJoints: [(HandJoint, HandJoint, HandJoint)] = [
        (.indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerTip),
        (.middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerTip),
        (.ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerTip),
        (.littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerTip)
    ]
    static let requiredJoints = Set(
        fingerTipJoints + palmJoints + flexionJoints.flatMap { [$0.0, $0.1, $0.2] }
    )

    let ballCenter: SIMD3<Float>
    let radius: Float
    let meanTipToPalmDistance: Float
    let meanFingerFlexion: Float

    static func capture(from frame: HandJointFrame) -> SqueezeHandMetrics? {
        guard frame.confidence(requiring: requiredJoints) == .good else { return nil }
        let tips = fingerTipJoints.compactMap { frame.joint($0)?.position }
        let palmPoints = palmJoints.compactMap { frame.joint($0)?.position }
        guard tips.count == fingerTipJoints.count,
              palmPoints.count == palmJoints.count,
              tips.allSatisfy(\.isFinite),
              palmPoints.allSatisfy(\.isFinite) else {
            return nil
        }

        let center = tips.reduce(.zero, +) / Float(tips.count)
        let radius = tips.map { simd_distance($0, center) }.reduce(0, +) / Float(tips.count)
        let palmCenter = palmPoints.reduce(.zero, +) / Float(palmPoints.count)
        let tipToPalm = tips.map { simd_distance($0, palmCenter) }.reduce(0, +) / Float(tips.count)
        let flexions = flexionJoints.compactMap { knuckle, intermediate, tip -> Float? in
            guard let knucklePosition = frame.joint(knuckle)?.position,
                  let intermediatePosition = frame.joint(intermediate)?.position,
                  let tipPosition = frame.joint(tip)?.position else {
                return nil
            }
            let proximal = intermediatePosition - knucklePosition
            let distal = tipPosition - intermediatePosition
            guard simd_length(proximal) > .ulpOfOne,
                  simd_length(distal) > .ulpOfOne else {
                return nil
            }
            return MovementMath.angle(between: proximal, and: distal)
        }
        guard flexions.count == flexionJoints.count else { return nil }
        let flexion = flexions.reduce(0, +) / Float(flexions.count)
        guard center.isFinite, radius.isFinite, tipToPalm.isFinite, flexion.isFinite else {
            return nil
        }
        return SqueezeHandMetrics(
            ballCenter: center,
            radius: radius,
            meanTipToPalmDistance: tipToPalm,
            meanFingerFlexion: flexion
        )
    }
}

struct SqueezeHandSample: Equatable, Sendable {
    let hand: AffectedHand
    let timestamp: TimeInterval
    let metrics: SqueezeHandMetrics

    init(hand: AffectedHand, timestamp: TimeInterval, metrics: SqueezeHandMetrics) {
        self.hand = hand
        self.timestamp = timestamp
        self.metrics = metrics
    }

    init?(frame: HandJointFrame) {
        guard let metrics = SqueezeHandMetrics.capture(from: frame) else { return nil }
        self.init(hand: frame.hand, timestamp: frame.timestamp, metrics: metrics)
    }
}

struct SqueezeBaseline: Equatable, Sendable {
    let metrics: SqueezeHandMetrics

    init(metrics: SqueezeHandMetrics) {
        self.metrics = metrics
    }

    var ballCenter: SIMD3<Float> { metrics.ballCenter }
    var radius: Float { metrics.radius }

    func normalizedClosure(for current: SqueezeHandMetrics) -> Float {
        let distanceRange = max(metrics.meanTipToPalmDistance * 0.5, .ulpOfOne)
        let distanceClosure = simd_clamp(
            (metrics.meanTipToPalmDistance - current.meanTipToPalmDistance) / distanceRange,
            0,
            1
        )
        let flexionClosure = simd_clamp(
            (current.meanFingerFlexion - metrics.meanFingerFlexion) / (.pi / 2),
            0,
            1
        )
        return (distanceClosure + flexionClosure) / 2
    }
}

struct SqueezeGraspGate: Sendable {
    static let minimumRadius: Float = 0.025
    static let maximumRadius: Float = 0.065
    static let maximumRadiusVariation: Float = 0.18
    static let maximumCenterDriftFraction: Float = 0.18
    static let minimumCuppedFlexion: Float = 0.15

    let stabilityDuration: TimeInterval
    private(set) var baseline: SqueezeBaseline?
    private var candidateStartedAt: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var candidateMetrics: [SqueezeHandMetrics] = []

    init(stabilityDuration: TimeInterval = 1) {
        self.stabilityDuration = stabilityDuration
    }

    mutating func update(_ metrics: SqueezeHandMetrics, at timestamp: TimeInterval) -> SqueezeBaseline? {
        if let baseline { return baseline }
        guard Self.isPlausibleCup(metrics) else {
            resetCandidate()
            return nil
        }
        if let lastTimestamp, timestamp < lastTimestamp {
            resetCandidate()
        }
        self.lastTimestamp = timestamp
        if candidateStartedAt == nil {
            candidateStartedAt = timestamp
        }
        candidateMetrics.append(metrics)

        let meanRadius = candidateMetrics.map(\.radius).reduce(0, +) / Float(candidateMetrics.count)
        let minimum = candidateMetrics.map(\.radius).min() ?? metrics.radius
        let maximum = candidateMetrics.map(\.radius).max() ?? metrics.radius
        let meanCenter = candidateMetrics.map(\.ballCenter).reduce(.zero, +) / Float(candidateMetrics.count)
        let maximumCenterDrift = candidateMetrics
            .map { simd_distance($0.ballCenter, meanCenter) }
            .max() ?? 0
        guard meanRadius > .ulpOfOne,
              (maximum - minimum) / meanRadius <= Self.maximumRadiusVariation,
              maximumCenterDrift / meanRadius <= Self.maximumCenterDriftFraction else {
            resetCandidate()
            candidateStartedAt = timestamp
            lastTimestamp = timestamp
            candidateMetrics = [metrics]
            return nil
        }
        guard let candidateStartedAt,
              timestamp - candidateStartedAt >= stabilityDuration else {
            return nil
        }

        let count = Float(candidateMetrics.count)
        let averaged = SqueezeHandMetrics(
            ballCenter: candidateMetrics.map(\.ballCenter).reduce(.zero, +) / count,
            radius: meanRadius,
            meanTipToPalmDistance: candidateMetrics.map(\.meanTipToPalmDistance).reduce(0, +) / count,
            meanFingerFlexion: candidateMetrics.map(\.meanFingerFlexion).reduce(0, +) / count
        )
        let accepted = SqueezeBaseline(metrics: averaged)
        baseline = accepted
        return accepted
    }

    mutating func resetCandidate() {
        candidateStartedAt = nil
        lastTimestamp = nil
        candidateMetrics.removeAll(keepingCapacity: true)
    }

    mutating func resetForRecalibration() {
        baseline = nil
        resetCandidate()
    }

    private static func isPlausibleCup(_ metrics: SqueezeHandMetrics) -> Bool {
        metrics.ballCenter.isFinite &&
        metrics.radius.isFinite &&
        (minimumRadius...maximumRadius).contains(metrics.radius) &&
        metrics.meanTipToPalmDistance.isFinite &&
        metrics.meanTipToPalmDistance > 0 &&
        metrics.meanFingerFlexion.isFinite &&
        metrics.meanFingerFlexion >= minimumCuppedFlexion
    }
}

struct SqueezeFacePose: Equatable, Sendable {
    let ballCenter: SIMD3<Float>
    let radius: Float

    func surfacePosition(toward viewerPosition: SIMD3<Float>) -> SIMD3<Float> {
        let direction = viewerPosition - ballCenter
        guard simd_length(direction) > .ulpOfOne else { return ballCenter }
        return ballCenter + simd_normalize(direction) * radius
    }
}

enum SqueezeEvent: Equatable, Sendable {
    case waitingForGrasp
    case stabilizingGrasp
    case paused
    case active(closure: Float, phase: SqueezeRepDetector.Phase)
    case repCompleted(completed: Int, goal: Int, isComplete: Bool)
    case complete
}

struct SqueezeSession: Sendable {
    static let graspStatusLabel = "Grasp pose detected (not object verified)"

    let affectedHand: AffectedHand
    let prescribedRepetitions: Int
    private var detector: SqueezeRepDetector
    private var graspGate = SqueezeGraspGate()
    private let isSimulated: Bool

    private(set) var facePose: SqueezeFacePose?
    private(set) var normalizedClosure: Float = 0
    private(set) var result: GameplayResult?

    init(prescription: Prescription) {
        self.init(
            affectedHand: prescription.affectedHand,
            goal: prescription.squeezeRepetitions,
            closeThreshold: prescription.squeezeCloseThreshold,
            reopenThreshold: prescription.squeezeReopenThreshold,
            holdSeconds: prescription.squeezeHoldSeconds
        )
    }

    init(
        affectedHand: AffectedHand,
        goal: Int,
        closeThreshold: Float,
        reopenThreshold: Float,
        holdSeconds: TimeInterval,
        isSimulated: Bool = false
    ) {
        self.affectedHand = affectedHand
        prescribedRepetitions = max(1, goal)
        self.isSimulated = isSimulated
        detector = SqueezeRepDetector(
            closeThreshold: closeThreshold,
            reopenThreshold: reopenThreshold,
            holdSeconds: holdSeconds
        )
    }

    init(
        repetitions: Int,
        closeThreshold: Float,
        reopenThreshold: Float,
        holdSeconds: TimeInterval
    ) {
        self.init(
            affectedHand: .right,
            goal: repetitions,
            closeThreshold: closeThreshold,
            reopenThreshold: reopenThreshold,
            holdSeconds: holdSeconds
        )
    }

    var completedRepetitions: Int { detector.completedRepetitions }
    var phase: SqueezeRepDetector.Phase { detector.phase }
    var isComplete: Bool { completedRepetitions >= prescribedRepetitions }
    var progress: SessionProgress {
        SessionProgress(
            completed: completedRepetitions,
            goal: prescribedRepetitions,
            partial: isComplete ? 0 : Double(normalizedClosure)
        )
    }
    var statusLabel: String? {
        graspGate.baseline == nil ? nil : Self.graspStatusLabel
    }

    mutating func process(frame: HandJointFrame?) -> SqueezeEvent {
        guard let frame, let sample = SqueezeHandSample(frame: frame) else {
            pause(requiresRecalibration: false)
            return .paused
        }
        return process(sample: sample)
    }

    mutating func process(sample: SqueezeHandSample?) -> SqueezeEvent {
        guard !isComplete else { return .complete }
        guard let sample, sample.hand == affectedHand else {
            facePose = nil
            detector.resetPartial()
            normalizedClosure = 0
            graspGate.resetCandidate()
            return .waitingForGrasp
        }

        if graspGate.baseline == nil {
            guard let baseline = graspGate.update(sample.metrics, at: sample.timestamp) else {
                facePose = nil
                return .stabilizingGrasp
            }
            facePose = SqueezeFacePose(ballCenter: baseline.ballCenter, radius: baseline.radius)
            normalizedClosure = 0
            return .active(closure: 0, phase: detector.phase)
        }

        guard let baseline = graspGate.baseline else { return .waitingForGrasp }
        facePose = SqueezeFacePose(ballCenter: sample.metrics.ballCenter, radius: baseline.radius)
        normalizedClosure = baseline.normalizedClosure(for: sample.metrics)
        let completedRep = detector.update(
            closure: normalizedClosure,
            at: sample.timestamp,
            isTracked: true
        )
        if completedRep {
            normalizedClosure = 0
            let complete = isComplete
            if complete {
                result = GameplayResult(
                    exercise: .squeeze,
                    prescribedDose: prescribedRepetitions,
                    completedDose: completedRepetitions,
                    trackingNote: outcomeTrackingNote
                )
            }
            return .repCompleted(
                completed: completedRepetitions,
                goal: prescribedRepetitions,
                isComplete: complete
            )
        }
        return .active(closure: normalizedClosure, phase: detector.phase)
    }

    mutating func pause(requiresRecalibration: Bool) {
        guard !isComplete else { return }
        facePose = nil
        normalizedClosure = 0
        detector.resetPartial()
        graspGate.resetCandidate()
        if requiresRecalibration {
            graspGate.resetForRecalibration()
        }
    }

    mutating func update(closure: Float, at timestamp: TimeInterval, isTracked: Bool) -> Bool {
        guard !isComplete else { return false }
        let completedRep = detector.update(closure: closure, at: timestamp, isTracked: isTracked)
        return completedRep && isComplete
    }

    private var outcomeTrackingNote: String {
        let source = isSimulated ? "Simulated from explicit Demo Mode samples" : "Measured from affected-hand fingertip-to-palm distance and finger flexion"
        return "\(source); grasp pose inferred, not object verified"
    }
}

private extension SIMD3 where Scalar == Float {
    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
