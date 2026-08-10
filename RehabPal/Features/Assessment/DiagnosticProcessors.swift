import Foundation
import simd

enum WristAssessmentTarget: String, CaseIterable, Equatable, Sendable {
    case center
    case forward
    case backward
    case left
    case right

    var title: String { rawValue.capitalized }
}

enum WristDiagnosticEvent: Equatable, Sendable {
    case waitingForCalibration
    case ready(target: WristAssessmentTarget, attempt: Int, goal: Int)
    case holding(target: WristAssessmentTarget, elapsed: TimeInterval, attempt: Int, goal: Int)
    case returnToNeutral(target: WristAssessmentTarget, attempt: Int, goal: Int)
    case attemptCompleted(completed: Int, goal: Int, nextTarget: WristAssessmentTarget)
    case completed(AssessmentResult.WristResult)
    case paused
}

/// Pure fixed-condition processor for the five-target wrist diagnostic.
struct WristDiagnosticProcessor: Sendable {
    static let targetDegrees: Float = 20
    static let targetToleranceDegrees: Float = 5
    static let offAxisToleranceDegrees: Float = 5
    static let holdSeconds: TimeInterval = 0.5
    static let neutralReturnToleranceDegrees: Float = 5

    let affectedHand: AffectedHand
    let targetSequence: [WristAssessmentTarget]
    let isSimulated: Bool
    let maximumInterFrameGap: TimeInterval
    let configuration: WristDiagnosticPrescription

    private(set) var completedAttempts = 0
    private(set) var result: AssessmentResult.WristResult?
    private var calibration: WristNeutralCalibration?
    private var holdStartedAt: TimeInterval?
    private var holdPrimarySamplesDegrees: [Float] = []
    private var holdTargetErrorsDegrees: [Float] = []
    private var attemptTargetErrorsDegrees: [Float] = []
    private var attemptHoldJitterDegrees: [Float] = []
    private var validFrameCount = 0
    private var requiredFrameCount = 0
    private var lastFrameTimestamp: TimeInterval?
    private var lastObservedFrameTimestamp: TimeInterval?
    private var lastObservedFrameWasValid = false
    private var lastObservationSequence: Int?
    private var isReturningToNeutral = false

    init(
        affectedHand: AffectedHand,
        attemptsPerTarget: Int,
        isSimulated: Bool = false,
        maximumInterFrameGap: TimeInterval = 0.1,
        configuration: WristDiagnosticPrescription? = nil
    ) {
        self.affectedHand = affectedHand
        self.isSimulated = isSimulated
        self.maximumInterFrameGap = max(0.001, maximumInterFrameGap)
        let attempts = max(1, attemptsPerTarget)
        self.configuration = configuration ?? WristDiagnosticPrescription(
            attemptsPerDirection: attempts,
            targetDegrees: Self.targetDegrees,
            targetToleranceDegrees: Self.targetToleranceDegrees,
            offAxisToleranceDegrees: Self.offAxisToleranceDegrees,
            holdSeconds: Self.holdSeconds,
            neutralReturnToleranceDegrees: Self.neutralReturnToleranceDegrees
        )
        targetSequence = WristAssessmentTarget.allCases.flatMap { target in
            Array(repeating: target, count: attempts)
        }
    }

    var isCalibrated: Bool { calibration != nil }
    var isComplete: Bool { completedAttempts == targetSequence.count }
    var currentTarget: WristAssessmentTarget? {
        guard !isComplete else { return nil }
        return targetSequence[completedAttempts]
    }
    var trackingConfidence: Float {
        requiredFrameCount == 0 ? 0 : Float(validFrameCount) / Float(requiredFrameCount)
    }
    var latestInputTimestamp: TimeInterval? { lastObservedFrameTimestamp }
    var progress: SessionProgress {
        let partial: Double
        if let holdStartedAt, let lastFrameTimestamp, !isReturningToNeutral {
            partial = min(max((lastFrameTimestamp - holdStartedAt) / configuration.holdSeconds, 0), 1)
        } else {
            partial = isReturningToNeutral ? 1 : 0
        }
        return SessionProgress(
            completed: completedAttempts,
            goal: targetSequence.count,
            partial: isComplete ? 0 : partial
        )
    }

    mutating func process(observation: HandJointFrameObservation) -> WristDiagnosticEvent {
        guard observation.sequence != lastObservationSequence else {
            if !isCalibrated { return .waitingForCalibration }
            return lastObservedFrameWasValid
                ? currentEvent(at: observation.frame?.timestamp ?? observation.timestamp)
                : .paused
        }
        lastObservationSequence = observation.sequence
        return process(frame: observation.frame)
    }

    mutating func process(frame: HandJointFrame?) -> WristDiagnosticEvent {
        guard !isComplete else {
            return result.map(WristDiagnosticEvent.completed) ?? .paused
        }
        guard let frame else {
            requiredFrameCount += 1
            lastObservedFrameWasValid = false
            resetPartialAttempt()
            return calibration == nil ? .waitingForCalibration : .paused
        }
        if let lastObservedFrameTimestamp,
           frame.timestamp <= lastObservedFrameTimestamp {
            if calibration == nil { return .waitingForCalibration }
            return lastObservedFrameWasValid
                ? currentEvent(at: frame.timestamp)
                : .paused
        }
        lastObservedFrameTimestamp = frame.timestamp
        requiredFrameCount += 1
        guard frame.isForAffectedHand(affectedHand) else {
            lastObservedFrameWasValid = false
            resetPartialAttempt()
            return calibration == nil ? .waitingForCalibration : .paused
        }

        if calibration == nil {
            guard let captured = WristNeutralCalibration.capture(from: frame) else {
                lastObservedFrameWasValid = false
                return .waitingForCalibration
            }
            calibration = captured
            lastFrameTimestamp = frame.timestamp
            lastObservedFrameWasValid = true
            validFrameCount += 1
            return .ready(target: targetSequence[completedAttempts], attempt: completedAttempts + 1, goal: targetSequence.count)
        }

        guard frame.confidence(requiring: Set([.wrist])) == .good,
              let wrist = frame.joint(.wrist)?.transform,
              Self.isFinite(wrist),
              let calibration else {
            lastObservedFrameWasValid = false
            resetPartialAttempt()
            return .paused
        }
        let previousFrameTimestamp = lastFrameTimestamp
        lastFrameTimestamp = frame.timestamp
        let tilt = MovementMath.wristTiltUnclamped(
            reference: calibration.wristTransform,
            current: wrist
        )
        let pitchDegrees = tilt.pitch * 180 / .pi
        let rollDegrees = tilt.roll * 180 / .pi
        guard pitchDegrees.isFinite, rollDegrees.isFinite else {
            lastObservedFrameWasValid = false
            resetPartialAttempt()
            return .paused
        }
        lastObservedFrameWasValid = true
        validFrameCount += 1
        let target = targetSequence[completedAttempts]

        if !isReturningToNeutral,
           holdStartedAt != nil,
           let previousFrameTimestamp,
           frame.timestamp - previousFrameTimestamp > maximumInterFrameGap + 0.000_001 {
            clearHold()
        }

        if isReturningToNeutral {
            guard isNeutral(pitchDegrees: pitchDegrees, rollDegrees: rollDegrees) else {
                return .returnToNeutral(target: target, attempt: completedAttempts + 1, goal: targetSequence.count)
            }
            finishAttempt()
            if isComplete, let result {
                return .completed(result)
            }
            return .attemptCompleted(
                completed: completedAttempts,
                goal: targetSequence.count,
                nextTarget: targetSequence[completedAttempts]
            )
        }

        guard let sample = targetSample(
            target: target,
            pitchDegrees: pitchDegrees,
            rollDegrees: rollDegrees
        ) else {
            clearHold()
            return .ready(target: target, attempt: completedAttempts + 1, goal: targetSequence.count)
        }

        if holdStartedAt == nil {
            holdStartedAt = frame.timestamp
        }
        holdPrimarySamplesDegrees.append(sample.primaryDegrees)
        holdTargetErrorsDegrees.append(sample.targetErrorDegrees)
        let elapsed = max(0, frame.timestamp - (holdStartedAt ?? frame.timestamp))
        guard elapsed + 0.000_001 >= configuration.holdSeconds else {
            return .holding(
                target: target,
                elapsed: elapsed,
                attempt: completedAttempts + 1,
                goal: targetSequence.count
            )
        }
        isReturningToNeutral = true
        return .returnToNeutral(target: target, attempt: completedAttempts + 1, goal: targetSequence.count)
    }

    mutating func pause(requiresRecalibration: Bool) {
        guard !isComplete else { return }
        resetPartialAttempt()
        if requiresRecalibration {
            calibration = nil
            lastFrameTimestamp = nil
        }
    }

    @discardableResult
    mutating func completeAssistedAttempt() -> Bool {
        guard !isComplete else { return false }
        let before = completedAttempts
        resetPartialAttempt()
        holdPrimarySamplesDegrees = [configuration.targetDegrees]
        holdTargetErrorsDegrees = [0]
        finishAttempt()
        return completedAttempts == before + 1
    }

    static func controlScore(
        targetErrorsDegrees: [Float],
        holdJitterDegrees: [Float]
    ) -> Int {
        let meanError = mean(targetErrorsDegrees)
        let meanJitter = mean(holdJitterDegrees)
        let rawScore = 100 - 2 * meanError - 3 * meanJitter
        return Int(min(max(rawScore.rounded(), 0), 100))
    }

    static func targetErrorDegrees(
        primaryDegrees: Float,
        targetDegrees: Float,
        offAxisDegrees: Float
    ) -> Float {
        hypot(primaryDegrees - targetDegrees, offAxisDegrees)
    }

    private mutating func finishAttempt() {
        attemptTargetErrorsDegrees.append(Self.mean(holdTargetErrorsDegrees))
        attemptHoldJitterDegrees.append(Self.standardDeviation(holdPrimarySamplesDegrees))
        completedAttempts += 1
        clearHold()
        isReturningToNeutral = false
        if isComplete {
            result = AssessmentResult.WristResult(
                controlScore: Self.controlScore(
                    targetErrorsDegrees: attemptTargetErrorsDegrees,
                    holdJitterDegrees: attemptHoldJitterDegrees
                ),
                trackingConfidence: trackingConfidence
            )
        }
    }

    private mutating func resetPartialAttempt() {
        clearHold()
        isReturningToNeutral = false
    }

    private mutating func clearHold() {
        holdStartedAt = nil
        holdPrimarySamplesDegrees.removeAll(keepingCapacity: true)
        holdTargetErrorsDegrees.removeAll(keepingCapacity: true)
    }

    private func currentEvent(at timestamp: TimeInterval) -> WristDiagnosticEvent {
        guard let target = currentTarget else {
            return result.map(WristDiagnosticEvent.completed) ?? .paused
        }
        if isReturningToNeutral {
            return .returnToNeutral(target: target, attempt: completedAttempts + 1, goal: targetSequence.count)
        }
        if let holdStartedAt {
            return .holding(
                target: target,
                elapsed: max(0, timestamp - holdStartedAt),
                attempt: completedAttempts + 1,
                goal: targetSequence.count
            )
        }
        return .ready(target: target, attempt: completedAttempts + 1, goal: targetSequence.count)
    }

    private func targetSample(
        target: WristAssessmentTarget,
        pitchDegrees: Float,
        rollDegrees: Float
    ) -> (primaryDegrees: Float, targetErrorDegrees: Float)? {
        let primary: Float
        let offAxis: Float
        let targetValue: Float
        switch target {
        case .center:
            guard isNeutral(pitchDegrees: pitchDegrees, rollDegrees: rollDegrees) else { return nil }
            primary = max(abs(pitchDegrees), abs(rollDegrees))
            offAxis = min(abs(pitchDegrees), abs(rollDegrees))
            targetValue = 0
        case .forward:
            primary = pitchDegrees
            offAxis = rollDegrees
            targetValue = configuration.targetDegrees
        case .backward:
            primary = pitchDegrees
            offAxis = rollDegrees
            targetValue = -configuration.targetDegrees
        case .left:
            primary = rollDegrees
            offAxis = pitchDegrees
            targetValue = -configuration.targetDegrees
        case .right:
            primary = rollDegrees
            offAxis = pitchDegrees
            targetValue = configuration.targetDegrees
        }
        guard abs(primary - targetValue) <= configuration.targetToleranceDegrees,
              abs(offAxis) <= configuration.offAxisToleranceDegrees else {
            return nil
        }
        return (
            primary,
            Self.targetErrorDegrees(
                primaryDegrees: primary,
                targetDegrees: targetValue,
                offAxisDegrees: offAxis
            )
        )
    }

    private func isNeutral(pitchDegrees: Float, rollDegrees: Float) -> Bool {
        abs(pitchDegrees) <= configuration.neutralReturnToleranceDegrees &&
        abs(rollDegrees) <= configuration.neutralReturnToleranceDegrees
    }

    private static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func standardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let average = mean(values)
        let variance = values.map { value in
            let difference = value - average
            return difference * difference
        }.reduce(0, +) / Float(values.count)
        return sqrt(variance)
    }

    private static func isFinite(_ transform: simd_float4x4) -> Bool {
        [
            transform.columns.0,
            transform.columns.1,
            transform.columns.2,
            transform.columns.3
        ].allSatisfy { column in
            column.x.isFinite && column.y.isFinite && column.z.isFinite && column.w.isFinite
        }
    }
}

enum WristDiagnosticAssistedProgressAction {
    @discardableResult
    static func process(
        processor: inout WristDiagnosticProcessor,
        nextTimestamp: inout TimeInterval
    ) -> Bool {
        guard !processor.isComplete else { return false }
        nextTimestamp = max(
            nextTimestamp,
            (processor.latestInputTimestamp ?? nextTimestamp) + 0.01
        )
        let before = processor.completedAttempts
        guard processor.completeAssistedAttempt() else { return false }
        nextTimestamp += processor.configuration.holdSeconds + 0.2
        return processor.completedAttempts == before + 1
    }
}

struct FingerROMMetrics: Equatable, Sendable {
    let interiorAngles: SIMD3<Float>
    let oppositionDistance: Float?

    var flexionAngles: SIMD3<Float> {
        SIMD3<Float>(
            simd_clamp(180 - interiorAngles.x, 0, 180),
            simd_clamp(180 - interiorAngles.y, 0, 180),
            simd_clamp(180 - interiorAngles.z, 0, 180)
        )
    }
    var totalFlexion: Float {
        flexionAngles.x + flexionAngles.y + flexionAngles.z
    }

    static func requiredJoints(for digit: HandDigit) -> [HandJoint] {
        switch digit {
        case .thumb:
            [.thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip, .littleFingerTip]
        case .index:
            [.indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip]
        case .middle:
            [.middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip]
        case .ring:
            [.ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip]
        case .little:
            [.littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip]
        }
    }

    static func capture(from frame: HandJointFrame, digit: HandDigit) -> FingerROMMetrics? {
        let required = requiredJoints(for: digit)
        guard frame.confidence(requiring: Set(required)) == .good else { return nil }
        let angleJoints = digit == .thumb ? Array(required.prefix(4)) : required
        let points = angleJoints.compactMap { frame.joint($0)?.position }
        guard points.count == angleJoints.count,
              points.allSatisfy(\.diagnosticIsFinite) else {
            return nil
        }

        let angles: SIMD3<Float>
        if digit == .thumb {
            angles = [
                interiorAngle(points[0], points[1], points[2]),
                interiorAngle(points[1], points[2], points[3]),
                180
            ]
        } else {
            angles = [
                interiorAngle(points[0], points[1], points[2]),
                interiorAngle(points[1], points[2], points[3]),
                interiorAngle(points[2], points[3], points[4])
            ]
        }
        guard angles.diagnosticIsFinite else { return nil }
        let opposition: Float?
        if digit == .thumb {
            guard let littleTip = frame.joint(.littleFingerTip)?.position,
                  littleTip.diagnosticIsFinite else {
                return nil
            }
            opposition = simd_distance(points.last!, littleTip)
        } else {
            opposition = nil
        }
        return FingerROMMetrics(interiorAngles: angles, oppositionDistance: opposition)
    }

    private static func interiorAngle(
        _ first: SIMD3<Float>,
        _ middle: SIMD3<Float>,
        _ last: SIMD3<Float>
    ) -> Float {
        MovementMath.angle(between: first - middle, and: last - middle) * 180 / .pi
    }
}

enum FingerDiagnosticAssistedProgressAction {
    @discardableResult
    static func process(
        processor: inout FingerROMDiagnosticProcessor,
        nextTimestamp: inout TimeInterval
    ) -> Bool {
        guard !processor.isComplete, processor.currentDigit != nil else { return false }
        nextTimestamp = max(
            nextTimestamp,
            (processor.latestInputTimestamp ?? nextTimestamp) + 0.01
        )
        let before = processor.completedAttempts
        guard processor.completeAssistedAttempt() else { return false }
        nextTimestamp += 0.1
        return processor.completedAttempts == before + 1
    }
}

struct FingerDiagnosticSample: Equatable, Sendable {
    let hand: AffectedHand
    let timestamp: TimeInterval
    let digit: HandDigit
    let metrics: FingerROMMetrics
}

enum FingerDiagnosticEvent: Equatable, Sendable {
    case stabilizingExtension(digit: HandDigit, attempt: Int, goal: Int)
    case capturingMotion(digit: HandDigit, attempt: Int, goal: Int)
    case returningToExtension(digit: HandDigit, attempt: Int, goal: Int)
    case attemptCompleted(completed: Int, goal: Int, nextDigit: HandDigit)
    case completed([HandDigit: DigitROMSummary])
    case paused
}

/// Pure sequential five-digit ROM state machine. Both live joint frames and
/// explicit Demo Mode samples enter through this same processor.
struct FingerROMDiagnosticProcessor: Sendable {
    static let extensionStabilitySeconds: TimeInterval = 0.3
    static let extensionStabilityToleranceDegrees: Float = 3
    static let minimumTotalExcursionDegrees: Float = 15
    static let extensionReturnToleranceDegrees: Float = 8
    static let thumbOppositionReduction: Float = 0.25
    static let thumbOppositionReturnTolerance: Float = 0.10

    let affectedHand: AffectedHand
    let digitSequence: [HandDigit]
    let isSimulated: Bool
    let maximumInterFrameGap: TimeInterval
    let configuration: FingerDiagnosticPrescription

    private(set) var completedAttempts = 0
    private(set) var result: [HandDigit: DigitROMSummary]?
    private(set) var attempts: [HandDigit: [FingerROMAttempt]] = [:]
    private var extensionStartedAt: TimeInterval?
    private var extensionCandidate: SIMD3<Float>?
    private var extensionBaseline: SIMD3<Float>?
    private var oppositionBaseline: Float?
    private var minimumFlexion: SIMD3<Float>?
    private var maximumFlexion: SIMD3<Float>?
    private var reachedExcursion = false
    private var lastTimestamp: TimeInterval?
    private var lastObservedFrameTimestamp: TimeInterval?
    private var lastObservedFrameWasValid = false
    private var lastObservationSequence: Int?
    private var validFrameCount = 0
    private var requiredFrameCount = 0
    private var attemptValidFrameCount = 0
    private var attemptRequiredFrameCount = 0

    init(
        affectedHand: AffectedHand,
        attemptsPerDigit: Int = 2,
        isSimulated: Bool = false,
        maximumInterFrameGap: TimeInterval = 0.1,
        configuration: FingerDiagnosticPrescription? = nil
    ) {
        self.affectedHand = affectedHand
        self.isSimulated = isSimulated
        self.maximumInterFrameGap = max(0.001, maximumInterFrameGap)
        let attempts = max(1, attemptsPerDigit)
        self.configuration = configuration ?? FingerDiagnosticPrescription(
            attemptsPerDigit: attempts,
            extensionStabilitySeconds: Self.extensionStabilitySeconds,
            extensionStabilityToleranceDegrees: Self.extensionStabilityToleranceDegrees,
            minimumTotalExcursionDegrees: Self.minimumTotalExcursionDegrees,
            extensionReturnToleranceDegrees: Self.extensionReturnToleranceDegrees,
            thumbOppositionReduction: Self.thumbOppositionReduction,
            thumbOppositionReturnTolerance: Self.thumbOppositionReturnTolerance
        )
        digitSequence = HandDigit.allCases.flatMap { digit in
            Array(repeating: digit, count: attempts)
        }
    }

    var isComplete: Bool { completedAttempts == digitSequence.count }
    var isCalibrated: Bool { extensionBaseline != nil }
    var currentDigit: HandDigit? {
        guard !isComplete else { return nil }
        return digitSequence[completedAttempts]
    }
    var trackingConfidence: Double {
        requiredFrameCount == 0 ? 0 : Double(validFrameCount) / Double(requiredFrameCount)
    }
    var latestInputTimestamp: TimeInterval? { lastObservedFrameTimestamp }
    var progress: SessionProgress {
        let partial: Double
        if reachedExcursion {
            partial = 1
        } else if let extensionBaseline, let maximumFlexion {
            let excursion = simd.max(maximumFlexion - extensionBaseline, SIMD3<Float>.zero)
            partial = min(max(Double(excursion.x + excursion.y + excursion.z) / Double(configuration.minimumTotalExcursionDegrees), 0), 1)
        } else {
            partial = 0
        }
        return SessionProgress(
            completed: completedAttempts,
            goal: digitSequence.count,
            partial: isComplete ? 0 : partial
        )
    }

    mutating func process(observation: HandJointFrameObservation) -> FingerDiagnosticEvent {
        guard observation.sequence != lastObservationSequence else {
            guard let digit = currentDigit else {
                return result.map(FingerDiagnosticEvent.completed) ?? .paused
            }
            return lastObservedFrameWasValid ? currentEvent(digit: digit) : .paused
        }
        lastObservationSequence = observation.sequence
        return process(frame: observation.frame)
    }

    mutating func process(frame: HandJointFrame?) -> FingerDiagnosticEvent {
        guard !isComplete, let digit = currentDigit else {
            return result.map(FingerDiagnosticEvent.completed) ?? .paused
        }
        guard let frame else {
            requiredFrameCount += 1
            attemptRequiredFrameCount += 1
            lastObservedFrameWasValid = false
            resetPartialAttempt()
            return .paused
        }
        if let lastObservedFrameTimestamp,
           frame.timestamp <= lastObservedFrameTimestamp {
            return lastObservedFrameWasValid ? currentEvent(digit: digit) : .paused
        }
        lastObservedFrameTimestamp = frame.timestamp
        requiredFrameCount += 1
        attemptRequiredFrameCount += 1
        guard frame.isForAffectedHand(affectedHand),
              let metrics = FingerROMMetrics.capture(from: frame, digit: digit) else {
            lastObservedFrameWasValid = false
            resetPartialAttempt()
            return .paused
        }
        lastObservedFrameWasValid = true
        validFrameCount += 1
        attemptValidFrameCount += 1
        return processValid(FingerDiagnosticSample(
            hand: frame.hand,
            timestamp: frame.timestamp,
            digit: digit,
            metrics: metrics
        ))
    }

    mutating func process(sample: FingerDiagnosticSample) -> FingerDiagnosticEvent {
        guard !isComplete, let digit = currentDigit else {
            return result.map(FingerDiagnosticEvent.completed) ?? .paused
        }
        if let lastObservedFrameTimestamp,
           sample.timestamp <= lastObservedFrameTimestamp {
            return lastObservedFrameWasValid ? currentEvent(digit: digit) : .paused
        }
        lastObservedFrameTimestamp = sample.timestamp
        requiredFrameCount += 1
        attemptRequiredFrameCount += 1
        guard sample.hand == affectedHand,
              sample.digit == digit,
              sample.metrics.interiorAngles.diagnosticIsFinite,
              sample.metrics.oppositionDistance?.isFinite != false,
              sample.digit != .thumb || sample.metrics.oppositionDistance != nil else {
            lastObservedFrameWasValid = false
            resetPartialAttempt()
            return .paused
        }
        lastObservedFrameWasValid = true
        validFrameCount += 1
        attemptValidFrameCount += 1
        return processValid(sample)
    }

    mutating func pause() {
        guard !isComplete else { return }
        resetPartialAttempt()
    }

    @discardableResult
    mutating func completeAssistedAttempt() -> Bool {
        guard !isComplete, let digit = currentDigit else { return false }
        let before = completedAttempts
        resetPartialAttempt()
        minimumFlexion = .zero
        maximumFlexion = [configuration.minimumTotalExcursionDegrees + 5, 10, 5]
        finishAttempt(for: digit)
        return completedAttempts == before + 1
    }

    private mutating func processValid(_ sample: FingerDiagnosticSample) -> FingerDiagnosticEvent {
        guard !isComplete, let digit = currentDigit else {
            return result.map(FingerDiagnosticEvent.completed) ?? .paused
        }
        guard lastTimestamp == nil || sample.timestamp > lastTimestamp! else {
            return currentEvent(digit: digit)
        }
        if let lastTimestamp,
           sample.timestamp - lastTimestamp > maximumInterFrameGap + 0.000_001 {
            resetPartialAttempt()
        }
        lastTimestamp = sample.timestamp
        let flexion = sample.metrics.flexionAngles

        guard let baseline = extensionBaseline else {
            guard digit != .thumb || (sample.metrics.oppositionDistance ?? 0) > 0 else {
                resetPartialAttempt()
                return .stabilizingExtension(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
            }
            if let extensionCandidate {
                let difference = simd_abs(flexion - extensionCandidate)
                if difference.max() > configuration.extensionStabilityToleranceDegrees {
                    self.extensionCandidate = flexion
                    extensionStartedAt = sample.timestamp
                    return .stabilizingExtension(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
                }
            } else {
                extensionCandidate = flexion
                extensionStartedAt = sample.timestamp
            }
            guard let extensionStartedAt,
                  sample.timestamp - extensionStartedAt + 0.000_001 >= configuration.extensionStabilitySeconds else {
                return .stabilizingExtension(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
            }
            extensionBaseline = flexion
            oppositionBaseline = sample.metrics.oppositionDistance
            minimumFlexion = flexion
            maximumFlexion = flexion
            return .capturingMotion(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
        }

        minimumFlexion = minimumFlexion.map { simd.min($0, flexion) } ?? flexion
        maximumFlexion = maximumFlexion.map { simd.max($0, flexion) } ?? flexion
        let positiveExcursion = simd.max((maximumFlexion ?? flexion) - baseline, SIMD3<Float>.zero)
        let totalExcursion = positiveExcursion.x + positiveExcursion.y + positiveExcursion.z
        if !reachedExcursion {
            let sufficientFlexion = totalExcursion >= configuration.minimumTotalExcursionDegrees
            let sufficientOpposition: Bool
            if digit == .thumb, let oppositionBaseline {
                sufficientOpposition = sample.metrics.oppositionDistance.map {
                    $0 <= oppositionBaseline * (1 - configuration.thumbOppositionReduction)
                } ?? false
            } else {
                sufficientOpposition = true
            }
            reachedExcursion = sufficientFlexion && sufficientOpposition
            guard reachedExcursion else {
                return .capturingMotion(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
            }
            return .returningToExtension(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
        }

        let returnDifference = simd_abs(flexion - baseline)
        let returnedFlexion = returnDifference.max() <= configuration.extensionReturnToleranceDegrees
        let returnedOpposition: Bool
        if digit == .thumb, let oppositionBaseline {
            returnedOpposition = sample.metrics.oppositionDistance.map {
                abs($0 - oppositionBaseline) <= oppositionBaseline * configuration.thumbOppositionReturnTolerance
            } ?? false
        } else {
            returnedOpposition = true
        }
        guard returnedFlexion && returnedOpposition else {
            return .returningToExtension(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
        }

        finishAttempt(for: digit)
        if isComplete, let result {
            return .completed(result)
        }
        return .attemptCompleted(
            completed: completedAttempts,
            goal: digitSequence.count,
            nextDigit: digitSequence[completedAttempts]
        )
    }

    private func currentEvent(digit: HandDigit) -> FingerDiagnosticEvent {
        if reachedExcursion {
            return .returningToExtension(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
        }
        if extensionBaseline != nil {
            return .capturingMotion(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
        }
        return .stabilizingExtension(digit: digit, attempt: completedAttempts + 1, goal: digitSequence.count)
    }

    private mutating func finishAttempt(for digit: HandDigit) {
        guard let minimumFlexion, let maximumFlexion else { return }
        let excursion = maximumFlexion - minimumFlexion
        let attemptConfidence = attemptRequiredFrameCount == 0
            ? 0
            : Double(attemptValidFrameCount) / Double(attemptRequiredFrameCount)
        let attempt = FingerROMAttempt(
            mcpExcursion: Double(excursion.x),
            pipExcursion: Double(excursion.y),
            dipExcursion: Double(excursion.z),
            maximumFlexion: Double(maximumFlexion.max()),
            maximumExtension: Double(minimumFlexion.min()),
            trackingConfidence: attemptConfidence
        )
        attempts[digit, default: []].append(attempt)
        completedAttempts += 1
        resetPartialAttempt()
        attemptValidFrameCount = 0
        attemptRequiredFrameCount = 0
        if isComplete {
            var session = HandROMAssessmentSession(attemptsPerDigit: attempts[digit]?.count ?? 1)
            for summaryDigit in HandDigit.allCases {
                for value in attempts[summaryDigit, default: []] {
                    _ = session.record(value, for: summaryDigit)
                }
            }
            result = Dictionary(uniqueKeysWithValues: HandDigit.allCases.compactMap { summaryDigit in
                session.summary(for: summaryDigit).map { (summaryDigit, $0) }
            })
        }
    }

    private mutating func resetPartialAttempt() {
        extensionStartedAt = nil
        extensionCandidate = nil
        extensionBaseline = nil
        oppositionBaseline = nil
        minimumFlexion = nil
        maximumFlexion = nil
        reachedExcursion = false
        lastTimestamp = nil
    }
}

private extension SIMD3 where Scalar == Float {
    var diagnosticIsFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
