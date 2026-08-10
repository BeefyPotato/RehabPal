import Foundation
import simd

struct BalanceTarget: Equatable, Sendable {
    let x: Float
    let z: Float

    var position: SIMD2<Float> { [x, z] }
}

struct BalanceTargetSchedule: Equatable, Sendable {
    static let maximumOffset: Float = 0.09
    static let ballStart = SIMD2<Float>(0, -0.066)
    static let minimumDistanceFromBallStart: Float = 0.084

    let targets: [BalanceTarget]

    init(seed: UInt64, targetCount: Int) {
        var generator = SeededGenerator(seed: seed)
        targets = (0..<max(1, targetCount)).map { _ in
            for _ in 0..<20 {
                let target = BalanceTarget(
                    x: Float.random(in: -Self.maximumOffset...Self.maximumOffset, using: &generator),
                    z: Float.random(in: -Self.maximumOffset...Self.maximumOffset, using: &generator)
                )
                if simd_distance(target.position, Self.ballStart) >= Self.minimumDistanceFromBallStart {
                    return target
                }
            }
            return BalanceTarget(x: 0, z: 0.066)
        }
    }
}

enum BalanceEvent: Equatable, Sendable {
    case waitingForCalibration
    case paused
    case active(WristTilt)
    case resetBall(WristTilt)
    case scored(completed: Int, goal: Int, tilt: WristTilt, isComplete: Bool)
}

/// Pure state machine for the calibrated balance game. RealityKit owns the
/// physics body; this processor owns safe scoring, calibration, and progress.
struct BalanceSession: Sendable {
    static let holeRadius: Float = 0.024

    let affectedHand: AffectedHand
    let goal: Int
    let schedule: BalanceTargetSchedule
    let isSimulated: Bool
    let calibrationFrameGoal = 25

    private(set) var completedSuccesses = 0
    private(set) var calibrationProgress = 0
    private(set) var result: GameplayResult?
    private var calibration: WristNeutralCalibration?
    private var lastCalibrationTimestamp: TimeInterval?
    private var shouldResetOnResume = false

    init(prescription: Prescription, seed: UInt64) {
        self.init(
            affectedHand: prescription.affectedHand,
            goal: prescription.balanceTargetCount,
            seed: seed,
            isSimulated: false
        )
    }

    init(
        affectedHand: AffectedHand,
        goal: Int,
        seed: UInt64,
        isSimulated: Bool = false
    ) {
        self.affectedHand = affectedHand
        self.goal = max(1, goal)
        self.isSimulated = isSimulated
        schedule = BalanceTargetSchedule(seed: seed, targetCount: goal)
    }

    var isCalibrated: Bool { calibration != nil }
    var requiredJoints: Set<HandJoint> {
        isCalibrated ? [.wrist] : WristNeutralCalibration.requiredJoints
    }
    var isComplete: Bool { completedSuccesses == goal }
    var progress: SessionProgress {
        SessionProgress(completed: completedSuccesses, goal: goal, partial: 0)
    }
    var currentTarget: BalanceTarget {
        schedule.targets[min(completedSuccesses, schedule.targets.count - 1)]
    }

    mutating func pause(requiresRecalibration: Bool) {
        guard !isComplete else { return }
        shouldResetOnResume = true
        if requiresRecalibration {
            clearCalibration()
        } else if !isCalibrated {
            resetCalibrationProgress()
        }
    }

    mutating func process(
        frame: HandJointFrame?,
        ballPosition: SIMD2<Float>,
        ballEscaped: Bool
    ) -> BalanceEvent {
        guard !isComplete else { return .paused }
        guard let frame, frame.isForAffectedHand(affectedHand) else {
            guard isCalibrated else {
                resetCalibrationProgress()
                return .waitingForCalibration
            }
            shouldResetOnResume = true
            return .paused
        }

        var calibratedThisFrame = false
        if calibration == nil {
            guard frame.timestamp.isFinite else {
                resetCalibrationProgress()
                return .waitingForCalibration
            }
            guard let captured = WristNeutralCalibration.capture(from: frame) else {
                resetCalibrationProgress()
                return .waitingForCalibration
            }
            if let lastCalibrationTimestamp {
                guard frame.timestamp >= lastCalibrationTimestamp else {
                    resetCalibrationProgress()
                    return .waitingForCalibration
                }
                guard frame.timestamp > lastCalibrationTimestamp else {
                    return .waitingForCalibration
                }
            }

            lastCalibrationTimestamp = frame.timestamp
            calibrationProgress += 1
            guard calibrationProgress == calibrationFrameGoal else {
                return .waitingForCalibration
            }
            calibration = captured
            calibratedThisFrame = true
        }
        guard let wrist = frame.joint(.wrist)?.transform,
              let calibration else {
            shouldResetOnResume = true
            return .paused
        }

        let tilt = calibration.tilt(for: wrist)
        if shouldResetOnResume {
            shouldResetOnResume = false
            return .resetBall(tilt)
        }
        if calibratedThisFrame {
            return .active(tilt)
        }
        if ballEscaped {
            return .resetBall(tilt)
        }
        guard simd_distance(ballPosition, currentTarget.position) <= Self.holeRadius else {
            return .active(tilt)
        }

        completedSuccesses += 1
        let completed = isComplete
        if completed {
            result = GameplayResult(
                exercise: .balance,
                prescribedDose: goal,
                completedDose: completedSuccesses,
                trackingNote: isSimulated
                    ? "Simulated from explicit Demo Mode physics ball drops"
                    : "Measured from calibrated affected-hand wrist tilt and physics ball drops"
            )
        }
        return .scored(
            completed: completedSuccesses,
            goal: goal,
            tilt: tilt,
            isComplete: completed
        )
    }

    private mutating func clearCalibration() {
        calibration = nil
        resetCalibrationProgress()
    }

    private mutating func resetCalibrationProgress() {
        calibrationProgress = 0
        lastCalibrationTimestamp = nil
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
