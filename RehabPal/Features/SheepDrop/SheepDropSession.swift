import Foundation
import simd

enum SheepDropPhase: Equatable, Sendable {
    case findingTable
    case waitingForHand
    case formingGrasp
    case carrying
    case falling
    case success
    case resetting
    case paused
    case complete
}

struct SheepDropObservation: Equatable, Sendable {
    let position: SIMD3<Float>
    let velocity: SIMD3<Float>
    let isRestingOnSpawnSurface: Bool
    let isOutsideSafeVolume: Bool
}

enum SheepDropEvent: Equatable, Sendable {
    case waitingForHand
    case formingGrasp
    case pickupBegan
    case carrying
    case released
    case falling
    case placementSucceeded(completed: Int, goal: Int, deadline: TimeInterval)
    case successWaiting(deadline: TimeInterval)
    case resetAfterSuccess
    case failedDropReset
    case trackingPaused(requiresRecalibration: Bool)
    case complete(GameplayResult)
}

enum SheepDropCommand: Equatable, Sendable {
    case none
    case pickup(position: SIMD3<Float>)
    case carry(position: SIMD3<Float>)
    case release
    case freeze(position: SIMD3<Float>)
    case reset(
        position: SIMD3<Float>,
        linearVelocity: SIMD3<Float>,
        angularVelocity: SIMD3<Float>
    )
}

struct SheepDropUpdate: Equatable, Sendable {
    let event: SheepDropEvent
    let command: SheepDropCommand
}

enum SheepDropAssistedProgressAction {
    @discardableResult
    static func process(
        session: inout SheepDropSession,
        nextTimestamp: inout TimeInterval
    ) -> Bool {
        guard session.phase != .complete else { return false }
        nextTimestamp = max(
            nextTimestamp,
            (session.latestInputTimestamp ?? nextTimestamp) + 0.01
        )
        session.prepareForAssistedProgress()
        let before = session.completedDrops
        let spawn = SheepDropObservation(
            position: session.spawnPosition,
            velocity: .zero,
            isRestingOnSpawnSurface: true,
            isOutsideSafeVolume: false
        )
        var base = nextTimestamp
        if session.phase == .resetting {
            _ = session.process(frame: nil, observation: spawn, at: base)
            base += 0.01
        }
        _ = session.process(
            frame: frame(hand: session.affectedHand, timestamp: base, center: session.spawnPosition, open: false),
            observation: spawn,
            at: base
        )
        _ = session.process(
            frame: frame(hand: session.affectedHand, timestamp: base + 0.25, center: session.spawnPosition, open: false),
            observation: spawn,
            at: base + 0.25
        )
        let overPen = SIMD3<Float>(0, 0.22, 0)
        let carried = SheepDropObservation(position: overPen, velocity: .zero, isRestingOnSpawnSurface: false, isOutsideSafeVolume: false)
        _ = session.process(
            frame: frame(hand: session.affectedHand, timestamp: base + 0.35, center: overPen, open: false),
            observation: carried,
            at: base + 0.35
        )
        _ = session.process(
            frame: frame(hand: session.affectedHand, timestamp: base + 0.40, center: overPen, open: true),
            observation: carried,
            at: base + 0.40
        )
        _ = session.process(
            frame: frame(hand: session.affectedHand, timestamp: base + 0.55, center: overPen, open: true),
            observation: carried,
            at: base + 0.55
        )
        let settled = SheepDropObservation(position: [0, 0.03, 0], velocity: .zero, isRestingOnSpawnSurface: false, isOutsideSafeVolume: false)
        _ = session.process(frame: nil, observation: settled, at: base + 0.60)
        _ = session.process(frame: nil, observation: settled, at: base + 0.85)
        _ = session.process(frame: nil, observation: settled, at: base + 1.65)
        nextTimestamp = base + 1.75
        return session.completedDrops == before + 1
    }

    private static func frame(
        hand: AffectedHand,
        timestamp: TimeInterval,
        center: SIMD3<Float>,
        open: Bool
    ) -> HandJointFrame {
        func tracked(_ position: SIMD3<Float>) -> HandJointSample {
            .tracked(transform: simd_float4x4(translation: position))
        }
        let offsets: [Float] = open
            ? [-0.05, -0.025, 0, 0.025, 0.05]
            : [-0.01, -0.005, 0, 0.005, 0.01]
        let tips: [HandJoint] = [.thumbTip, .indexFingerTip, .middleFingerTip, .ringFingerTip, .littleFingerTip]
        var joints: [HandJoint: HandJointSample] = [
            .wrist: tracked(center + [0, -0.08, 0]),
            .indexFingerKnuckle: tracked(center + [0.08, -0.08, 0]),
            .middleFingerKnuckle: tracked(center + [0, 0, 0]),
            .ringFingerKnuckle: tracked(center + [-0.08, -0.08, 0]),
            .littleFingerKnuckle: tracked(center + [0, -0.16, 0])
        ]
        for (tip, offset) in zip(tips, offsets) {
            joints[tip] = tracked(center + [offset, 0, 0])
        }
        return .synthetic(hand: hand, timestamp: timestamp, joints: joints)
    }
}

struct SheepDropSession: Sendable {
    static let pickupDwellDuration: TimeInterval = 0.25
    static let releaseDwellDuration: TimeInterval = 0.15
    static let releaseClusterRatio: Float = 0.95
    static let carryFilterTimeConstant: TimeInterval = 0.08
    static let settledDwellDuration: TimeInterval = 0.25
    static let maximumFallingObservationDuration: TimeInterval = 1.0
    static let successDisplayDuration: TimeInterval = 0.8
    static let maximumSettledSpeed: Float = 0.08
    static let maximumSettledHeightInRadii: Float = 2.5
    static let penInnerHalfExtent: Float = 0.168
    static let maximumCarryHeight: Float = 0.45
    static let maximumHorizontalCarryDistance: Float = 0.65
    private static let timestampTolerance: TimeInterval = 1e-9

    static let requiredJoints: Set<HandJoint> = [
        .wrist,
        .indexFingerKnuckle,
        .middleFingerKnuckle,
        .ringFingerKnuckle,
        .littleFingerKnuckle,
        .thumbTip,
        .indexFingerTip,
        .middleFingerTip,
        .ringFingerTip,
        .littleFingerTip
    ]

    let affectedHand: AffectedHand
    let goal: Int
    let isSimulated: Bool
    let spawnPosition: SIMD3<Float>
    let sheepCollisionRadius: Float

    private(set) var phase: SheepDropPhase = .waitingForHand
    private(set) var completedDrops = 0
    private(set) var result: GameplayResult?

    private var pickupDwellStartedAt: TimeInterval?
    private var releaseDwellStartedAt: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var filteredCentroid: SIMD3<Float>?
    private var carryOffset: SIMD3<Float>?
    private var lastFilterTimestamp: TimeInterval?
    private var lastSheepPosition: SIMD3<Float>
    private var phaseBeforePause: SheepDropPhase?
    private var releasedAt: TimeInterval?
    private var settledDwellStartedAt: TimeInterval?
    private var successDeadline: TimeInterval?
    private var isDirectlyGrabbed = false
    private var directGrabInterrupted = false

    init(
        affectedHand: AffectedHand,
        goal: Int,
        isSimulated: Bool = false,
        spawnPosition: SIMD3<Float>,
        sheepCollisionRadius: Float
    ) {
        self.affectedHand = affectedHand
        self.goal = max(1, goal)
        self.isSimulated = isSimulated
        self.spawnPosition = spawnPosition
        self.sheepCollisionRadius = max(0, sheepCollisionRadius)
        lastSheepPosition = spawnPosition
    }

    init(
        prescription: Prescription,
        isSimulated: Bool = false,
        spawnPosition: SIMD3<Float>,
        sheepCollisionRadius: Float
    ) {
        self.init(
            affectedHand: prescription.affectedHand,
            goal: prescription.sheepDropRepetitions,
            isSimulated: isSimulated,
            spawnPosition: spawnPosition,
            sheepCollisionRadius: sheepCollisionRadius
        )
    }

    var progress: SessionProgress {
        let partial: Double
        if phase == .formingGrasp,
           let pickupDwellStartedAt,
           let lastTimestamp {
            partial = min(
                1,
                max(0, (lastTimestamp - pickupDwellStartedAt) / Self.pickupDwellDuration)
            )
        } else {
            partial = 0
        }
        return SessionProgress(completed: completedDrops, goal: goal, partial: partial)
    }
    var latestInputTimestamp: TimeInterval? { lastTimestamp }

    mutating func prepareForAssistedProgress() {
        guard phase != .complete else { return }
        clearAttemptState()
        phaseBeforePause = nil
        phase = .waitingForHand
    }

    /// System-targeted drag input, matching the test 9-3 interaction route.
    /// This deliberately does not inspect or synthesize hand joints.
    mutating func beginDirectDrag(at position: SIMD3<Float>, timestamp: TimeInterval) -> SheepDropUpdate {
        guard phase != .complete, position.hasFiniteComponents, timestamp.isFinite else { return waitingUpdate() }
        lastTimestamp = max(lastTimestamp ?? timestamp, timestamp)
        pickupDwellStartedAt = nil
        releaseDwellStartedAt = nil
        clearCarryState()
        isDirectlyGrabbed = true
        directGrabInterrupted = false
        phase = .carrying
        lastSheepPosition = clampedCarryPosition(position)
        return SheepDropUpdate(event: .pickupBegan, command: .pickup(position: lastSheepPosition))
    }

    mutating func updateDirectDrag(to position: SIMD3<Float>, timestamp: TimeInterval) -> SheepDropUpdate {
        guard isDirectlyGrabbed, phase == .carrying, position.hasFiniteComponents else {
            return SheepDropUpdate(event: .waitingForHand, command: .none)
        }
        lastTimestamp = max(lastTimestamp ?? timestamp, timestamp)
        lastSheepPosition = clampedCarryPosition(position)
        return SheepDropUpdate(event: .carrying, command: .carry(position: lastSheepPosition))
    }

    mutating func endDirectDrag(timestamp: TimeInterval) -> SheepDropUpdate {
        guard isDirectlyGrabbed, phase == .carrying else {
            return SheepDropUpdate(event: .waitingForHand, command: .none)
        }
        isDirectlyGrabbed = false
        lastTimestamp = max(lastTimestamp ?? timestamp, timestamp)
        phase = .falling
        releasedAt = lastTimestamp
        settledDwellStartedAt = nil
        clearCarryState()
        return SheepDropUpdate(event: .released, command: .release)
    }

    /// Clears a drag that the shared tracking lifecycle interrupted. The
    /// physical body remains where the pause command froze/reset it, and a
    /// stale system gesture end cannot infer release or scoring.
    mutating func resumeAfterTrackingInterruption() -> SheepDropUpdate {
        guard phase == .paused, directGrabInterrupted else {
            if phase == .complete, let result {
                return SheepDropUpdate(event: .complete(result), command: .none)
            }
            return SheepDropUpdate(event: .waitingForHand, command: .none)
        }
        directGrabInterrupted = false
        isDirectlyGrabbed = false
        phaseBeforePause = nil
        clearAttemptState()
        phase = .waitingForHand
        return SheepDropUpdate(event: .waitingForHand, command: .none)
    }

    mutating func process(
        frame: HandJointFrame?,
        observation: SheepDropObservation,
        at timestamp: TimeInterval
    ) -> SheepDropUpdate {
        guard timestamp.isFinite else {
            return rejectInvalidTimestamp()
        }
        if let lastTimestamp, timestamp < lastTimestamp {
            return rejectInvalidTimestamp()
        }
        lastTimestamp = timestamp
        if observation.position.hasFiniteComponents {
            lastSheepPosition = observation.position
        }

        switch phase {
        case .findingTable, .waitingForHand, .formingGrasp:
            return processPickupCandidate(
                frame: frame,
                observation: observation,
                at: timestamp
            )
        case .carrying:
            return processCarry(frame: frame, observation: observation, at: timestamp)
        case .paused:
            if phaseBeforePause == .falling {
                phase = .falling
                phaseBeforePause = nil
                return processFalling(observation: observation, at: timestamp)
            }
            if phaseBeforePause == .carrying {
                phase = .carrying
                phaseBeforePause = nil
                return processCarry(frame: frame, observation: observation, at: timestamp)
            }
            if phaseBeforePause == .success {
                phase = .success
                phaseBeforePause = nil
                return processSuccess(at: timestamp)
            }
            if phaseBeforePause == .resetting {
                phase = .resetting
                phaseBeforePause = nil
                clearAttemptState()
                return waitingUpdate()
            }
            return waitingUpdate()
        case .falling:
            return processFalling(observation: observation, at: timestamp)
        case .success:
            return processSuccess(at: timestamp)
        case .resetting:
            clearAttemptState()
            return waitingUpdate()
        case .complete:
            guard let result else {
                return SheepDropUpdate(event: .falling, command: .none)
            }
            return SheepDropUpdate(event: .complete(result), command: .none)
        }
    }

    mutating func pause(requiresRecalibration: Bool) -> SheepDropUpdate {
        if phase == .complete, let result {
            return SheepDropUpdate(event: .complete(result), command: .none)
        }

        directGrabInterrupted = directGrabInterrupted || isDirectlyGrabbed
        isDirectlyGrabbed = false
        pickupDwellStartedAt = nil
        releaseDwellStartedAt = nil
        settledDwellStartedAt = nil
        let previousPhase = phase == .paused ? phaseBeforePause : phase
        phaseBeforePause = previousPhase
        phase = .paused

        if requiresRecalibration {
            if previousPhase == .success {
                releasedAt = nil
                clearCarryState()
                phaseBeforePause = .success
            } else {
                clearAttemptState()
                phaseBeforePause = previousPhase == .resetting
                    ? .resetting
                    : .waitingForHand
            }
            return SheepDropUpdate(
                event: .trackingPaused(requiresRecalibration: true),
                command: resetCommand
            )
        }
        return SheepDropUpdate(
            event: .trackingPaused(requiresRecalibration: false),
            command: .freeze(position: lastSheepPosition)
        )
    }

    /// Freezes an incomplete local hand measurement without entering the
    /// shared tracking-loss lifecycle or inferring an open-hand release.
    mutating func measurementUnavailable(
        observation: SheepDropObservation
    ) -> SheepDropUpdate {
        pickupDwellStartedAt = nil
        releaseDwellStartedAt = nil
        guard phase != .complete else {
            return result.map { SheepDropUpdate(event: .complete($0), command: .none) }
                ?? waitingUpdate()
        }
        if phase == .carrying {
            if observation.position.hasFiniteComponents {
                lastSheepPosition = observation.position
            }
            return SheepDropUpdate(
                event: .carrying,
                command: .freeze(position: lastSheepPosition)
            )
        }
        return waitingUpdate()
    }

    private mutating func processPickupCandidate(
        frame: HandJointFrame?,
        observation: SheepDropObservation,
        at timestamp: TimeInterval
    ) -> SheepDropUpdate {
        guard observation.isRestingOnSpawnSurface,
              let frame,
              frame.isForAffectedHand(affectedHand),
              let pose = FiveFingertipPose(
                frame: frame,
                sheepPosition: observation.position
              ),
              pose.isPickupEligible else {
            pickupDwellStartedAt = nil
            return waitingUpdate()
        }

        if pickupDwellStartedAt == nil {
            pickupDwellStartedAt = timestamp
        }
        phase = .formingGrasp
        guard let pickupDwellStartedAt,
              Self.hasElapsed(
                since: pickupDwellStartedAt,
                duration: Self.pickupDwellDuration,
                at: timestamp
              ) else {
            return SheepDropUpdate(event: .formingGrasp, command: .none)
        }

        self.pickupDwellStartedAt = nil
        phase = .carrying
        filteredCentroid = pose.centroid
        carryOffset = observation.position - pose.centroid
        lastFilterTimestamp = timestamp
        let position = clampedCarryPosition(observation.position)
        return SheepDropUpdate(
            event: .pickupBegan,
            command: .pickup(position: position)
        )
    }

    private mutating func processCarry(
        frame: HandJointFrame?,
        observation: SheepDropObservation,
        at timestamp: TimeInterval
    ) -> SheepDropUpdate {
        guard let frame,
              frame.isForAffectedHand(affectedHand),
              let pose = FiveFingertipPose(
                frame: frame,
                sheepPosition: observation.position
              ) else {
            return measurementUnavailable(observation: observation)
        }

        if pose.clusterRatio >= Self.releaseClusterRatio {
            if releaseDwellStartedAt == nil {
                releaseDwellStartedAt = timestamp
            }
        } else {
            releaseDwellStartedAt = nil
        }

        if let releaseDwellStartedAt,
           Self.hasElapsed(
            since: releaseDwellStartedAt,
            duration: Self.releaseDwellDuration,
            at: timestamp
           ) {
            self.releaseDwellStartedAt = nil
            phase = .falling
            releasedAt = timestamp
            settledDwellStartedAt = nil
            clearCarryState()
            return SheepDropUpdate(event: .released, command: .release)
        }

        let position = filteredCarryPosition(for: pose.centroid, at: timestamp)
        return SheepDropUpdate(
            event: .carrying,
            command: .carry(position: position)
        )
    }

    private mutating func rejectInvalidTimestamp() -> SheepDropUpdate {
        pickupDwellStartedAt = nil
        releaseDwellStartedAt = nil
        settledDwellStartedAt = nil

        switch phase {
        case .findingTable, .waitingForHand, .formingGrasp:
            return waitingUpdate()
        case .carrying:
            return SheepDropUpdate(
                event: .carrying,
                command: .freeze(position: lastSheepPosition)
            )
        case .falling:
            return SheepDropUpdate(
                event: .falling,
                command: .freeze(position: lastSheepPosition)
            )
        case .success:
            guard let successDeadline else {
                return SheepDropUpdate(
                    event: .trackingPaused(requiresRecalibration: false),
                    command: .freeze(position: lastSheepPosition)
                )
            }
            return SheepDropUpdate(
                event: .successWaiting(deadline: successDeadline),
                command: .none
            )
        case .resetting:
            return SheepDropUpdate(
                event: .trackingPaused(requiresRecalibration: false),
                command: .freeze(position: lastSheepPosition)
            )
        case .paused:
            return SheepDropUpdate(
                event: .trackingPaused(requiresRecalibration: false),
                command: .freeze(position: lastSheepPosition)
            )
        case .complete:
            guard let result else {
                return SheepDropUpdate(event: .falling, command: .none)
            }
            return SheepDropUpdate(event: .complete(result), command: .none)
        }
    }

    private mutating func waitingUpdate() -> SheepDropUpdate {
        phase = .waitingForHand
        return SheepDropUpdate(event: .waitingForHand, command: .none)
    }

    private mutating func processFalling(
        observation: SheepDropObservation,
        at timestamp: TimeInterval
    ) -> SheepDropUpdate {
        guard let releasedAt else {
            settledDwellStartedAt = nil
            return SheepDropUpdate(event: .falling, command: .none)
        }

        let positionIsFinite = observation.position.hasFiniteComponents
        let velocityIsFinite = observation.velocity.hasFiniteComponents
        let speed = velocityIsFinite
            ? simd_length(observation.velocity)
            : .infinity
        let insidePen = positionIsFinite &&
            abs(observation.position.x) <= Self.penInnerHalfExtent &&
            abs(observation.position.z) <= Self.penInnerHalfExtent
        let lowEnough = positionIsFinite &&
            observation.position.y <= sheepCollisionRadius * Self.maximumSettledHeightInRadii
        let slowEnough = speed.isFinite && speed <= Self.maximumSettledSpeed
        let settled = insidePen && lowEnough && slowEnough

        if observation.isOutsideSafeVolume ||
            (positionIsFinite && observation.position.y < -sheepCollisionRadius) ||
            (!insidePen && lowEnough && slowEnough) ||
            Self.hasElapsed(
                since: releasedAt,
                duration: Self.maximumFallingObservationDuration,
                at: timestamp
            ) {
            return resetFailedDrop()
        }

        guard settled else {
            settledDwellStartedAt = nil
            return SheepDropUpdate(event: .falling, command: .none)
        }
        if settledDwellStartedAt == nil {
            settledDwellStartedAt = timestamp
        }
        guard let settledDwellStartedAt,
              Self.hasElapsed(
                since: settledDwellStartedAt,
                duration: Self.settledDwellDuration,
                at: timestamp
              ) else {
            return SheepDropUpdate(event: .falling, command: .none)
        }

        self.settledDwellStartedAt = nil
        completedDrops = min(goal, completedDrops + 1)
        phase = .success
        let deadline = timestamp + Self.successDisplayDuration
        successDeadline = deadline
        return SheepDropUpdate(
            event: .placementSucceeded(
                completed: completedDrops,
                goal: goal,
                deadline: deadline
            ),
            command: .none
        )
    }

    private mutating func processSuccess(at timestamp: TimeInterval) -> SheepDropUpdate {
        guard let successDeadline else {
            phase = .resetting
            return SheepDropUpdate(event: .resetAfterSuccess, command: resetCommand)
        }
        guard timestamp + Self.timestampTolerance >= successDeadline else {
            return SheepDropUpdate(
                event: .successWaiting(deadline: successDeadline),
                command: .none
            )
        }

        if completedDrops >= goal {
            let completedResult = result ?? GameplayResult(
                exercise: .sheepDrop,
                prescribedDose: goal,
                completedDose: completedDrops,
                trackingNote: outcomeTrackingNote
            )
            result = completedResult
            phase = .complete
            return SheepDropUpdate(event: .complete(completedResult), command: .none)
        }

        phase = .resetting
        return SheepDropUpdate(event: .resetAfterSuccess, command: resetCommand)
    }

    private mutating func resetFailedDrop() -> SheepDropUpdate {
        clearAttemptState()
        phase = .resetting
        return SheepDropUpdate(event: .failedDropReset, command: resetCommand)
    }

    private mutating func filteredCarryPosition(
        for centroid: SIMD3<Float>,
        at timestamp: TimeInterval
    ) -> SIMD3<Float> {
        let previous = filteredCentroid ?? centroid
        let delta = max(0, timestamp - (lastFilterTimestamp ?? timestamp))
        let alpha = Float(1 - exp(-delta / Self.carryFilterTimeConstant))
        let filtered = previous + (centroid - previous) * alpha
        filteredCentroid = filtered
        lastFilterTimestamp = timestamp
        return clampedCarryPosition(filtered + (carryOffset ?? .zero))
    }

    private func clampedCarryPosition(_ position: SIMD3<Float>) -> SIMD3<Float> {
        var clamped = position
        clamped.y = min(Self.maximumCarryHeight, max(sheepCollisionRadius, clamped.y))
        let horizontal = SIMD2<Float>(clamped.x, clamped.z)
        let horizontalDistance = simd_length(horizontal)
        if horizontalDistance > Self.maximumHorizontalCarryDistance {
            let scaled = horizontal / horizontalDistance * Self.maximumHorizontalCarryDistance
            clamped.x = scaled.x
            clamped.z = scaled.y
        }
        return clamped
    }

    private mutating func clearCarryState() {
        filteredCentroid = nil
        carryOffset = nil
        lastFilterTimestamp = nil
    }

    private mutating func clearAttemptState() {
        pickupDwellStartedAt = nil
        releaseDwellStartedAt = nil
        releasedAt = nil
        settledDwellStartedAt = nil
        successDeadline = nil
        phaseBeforePause = nil
        clearCarryState()
    }

    private var resetCommand: SheepDropCommand {
        .reset(position: spawnPosition, linearVelocity: .zero, angularVelocity: .zero)
    }

    private var outcomeTrackingNote: String {
        if isSimulated {
            return "Simulated joint observations from explicit Demo Mode; five-fingertip pose and sheep physics processed identically"
        }
        return "Measured from RealityKit targeted system pinch/drag interaction and sheep physics"
    }

    private static func hasElapsed(
        since start: TimeInterval,
        duration: TimeInterval,
        at timestamp: TimeInterval
    ) -> Bool {
        timestamp - start + timestampTolerance >= duration
    }
}

struct FiveFingertipPose: Equatable, Sendable {
    static let minimumHandScale: Float = 0.04
    static let maximumHandScale: Float = 0.14
    static let pickupClusterRatio: Float = 0.62
    static let pickupReachRatio: Float = 0.75

    let tipPositions: [SIMD3<Float>]
    let centroid: SIMD3<Float>
    let handScale: Float
    let clusterRatio: Float
    let reachRatio: Float

    var isPickupEligible: Bool {
        clusterRatio <= Self.pickupClusterRatio &&
        reachRatio <= Self.pickupReachRatio
    }

    init?(frame: HandJointFrame, sheepPosition: SIMD3<Float>) {
        guard sheepPosition.hasFiniteComponents,
              frame.confidence(requiring: SheepDropSession.requiredJoints) == .good,
              let wrist = frame.joint(.wrist)?.position,
              wrist.hasFiniteComponents else {
            return nil
        }

        let knuckleJoints: [HandJoint] = [
            .indexFingerKnuckle,
            .middleFingerKnuckle,
            .ringFingerKnuckle,
            .littleFingerKnuckle
        ]
        let knucklePositions = knuckleJoints.compactMap { frame.joint($0)?.position }
        guard knucklePositions.count == knuckleJoints.count,
              knucklePositions.allSatisfy(\.hasFiniteComponents) else {
            return nil
        }
        let wristDistances = knucklePositions
            .map { simd_distance(wrist, $0) }
            .sorted()
        let scale = (wristDistances[1] + wristDistances[2]) / 2
        guard scale.isFinite,
              (Self.minimumHandScale...Self.maximumHandScale).contains(scale) else {
            return nil
        }

        let tipJoints: [HandJoint] = [
            .thumbTip,
            .indexFingerTip,
            .middleFingerTip,
            .ringFingerTip,
            .littleFingerTip
        ]
        let tips = tipJoints.compactMap { frame.joint($0)?.position }
        guard tips.count == tipJoints.count,
              tips.allSatisfy(\.hasFiniteComponents) else {
            return nil
        }

        let center = tips.reduce(SIMD3<Float>.zero, +) / Float(tips.count)
        var maximumSeparation: Float = 0
        for firstIndex in tips.indices {
            for secondIndex in tips.index(after: firstIndex)..<tips.endIndex {
                maximumSeparation = max(
                    maximumSeparation,
                    simd_distance(tips[firstIndex], tips[secondIndex])
                )
            }
        }
        let normalizedCluster = maximumSeparation / scale
        let normalizedReach = simd_distance(center, sheepPosition) / scale
        guard center.hasFiniteComponents,
              normalizedCluster.isFinite,
              normalizedReach.isFinite else {
            return nil
        }

        tipPositions = tips
        centroid = center
        handScale = scale
        clusterRatio = normalizedCluster
        reachRatio = normalizedReach
    }
}

private extension SIMD3 where Scalar == Float {
    var hasFiniteComponents: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
