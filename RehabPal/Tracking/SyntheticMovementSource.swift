import Foundation
import Observation
import simd

enum SyntheticSheepDropPose: Equatable, Sendable {
    case open
    case clustered
}

@MainActor
@Observable
final class SyntheticMovementSource: MovementObservationSource {
    private let hand: AffectedHand
    private(set) var latestObservation = MovementObservation(
        timestamp: 0,
        isTracked: true,
        wristPitch: 0,
        wristRoll: 0,
        closure: 0,
        thumbToIndexDistance: 0.08,
        quality: .good
    )
    private(set) var latestJointFrame: HandJointFrame?
    let isFallback = true

    init(hand: AffectedHand = .right) {
        self.hand = hand
        self.latestJointFrame = Self.jointFrame(
            hand: hand,
            timestamp: 0,
            observation: latestObservation
        )
    }

    func setWrist(direction: WristDirection, progress: Float, at timestamp: TimeInterval) {
        let value = min(max(progress, 0), 1) * 0.4
        latestObservation = MovementObservation(
            timestamp: timestamp,
            isTracked: true,
            wristPitch: direction == .forward ? value : direction == .backward ? -value : 0,
            wristRoll: direction == .right ? value : direction == .left ? -value : 0,
            closure: latestObservation.closure,
            thumbToIndexDistance: latestObservation.thumbToIndexDistance,
            quality: .good
        )
        publishJointFrame()
    }

    func setClosure(_ closure: Float, at timestamp: TimeInterval) {
        latestObservation = MovementObservation(
            timestamp: timestamp,
            isTracked: true,
            wristPitch: latestObservation.wristPitch,
            wristRoll: latestObservation.wristRoll,
            closure: min(max(closure, 0), 1),
            thumbToIndexDistance: 0.08 * (1 - closure),
            quality: .good
        )
        publishJointFrame()
    }

    func setTrackingVisible(_ visible: Bool, at timestamp: TimeInterval) {
        if visible {
            latestObservation = MovementObservation(
                timestamp: timestamp,
                isTracked: true,
                wristPitch: latestObservation.wristPitch,
                wristRoll: latestObservation.wristRoll,
                closure: latestObservation.closure,
                thumbToIndexDistance: latestObservation.thumbToIndexDistance,
                quality: .good
            )
        } else {
            latestObservation = .untracked(at: timestamp)
        }
        publishJointFrame()
    }

    /// Publishes a complete, hand-scale-valid five-fingertip frame in the
    /// caller's coordinate space. Sheep Drop supplies pen-local centers so its
    /// Demo Mode crosses the same processor boundary as live hand frames.
    func setSheepDropPose(
        _ pose: SyntheticSheepDropPose,
        centeredAt center: SIMD3<Float>,
        at timestamp: TimeInterval
    ) {
        let closure: Float = pose == .clustered ? 1 : 0
        latestObservation = MovementObservation(
            timestamp: timestamp,
            isTracked: true,
            wristPitch: 0,
            wristRoll: 0,
            closure: closure,
            thumbToIndexDistance: pose == .clustered ? 0.005 : 0.025,
            quality: .good
        )
        latestJointFrame = Self.sheepDropJointFrame(
            hand: hand,
            timestamp: timestamp,
            pose: pose,
            center: center
        )
    }

    private func publishJointFrame() {
        latestJointFrame = Self.jointFrame(
            hand: hand,
            timestamp: latestObservation.timestamp,
            observation: latestObservation
        )
    }

    private static func jointFrame(
        hand: AffectedHand,
        timestamp: TimeInterval,
        observation: MovementObservation
    ) -> HandJointFrame {
        guard observation.isTracked else {
            return .synthetic(hand: hand, timestamp: timestamp, joints: [.wrist: .untracked])
        }

        let wristTransform = MovementMath.wristTransform(
            pitch: observation.wristPitch,
            roll: observation.wristRoll
        )
        var joints = Dictionary(uniqueKeysWithValues: HandJoint.allCases.map { joint in
            (joint, HandJointSample.tracked(transform: wristTransform))
        })

        let tipDistance = observation.thumbToIndexDistance ?? 0.08
        joints[.thumbTip] = .tracked(transform: MovementMath.worldTransform(
            anchor: wristTransform,
            joint: simd_float4x4(translation: SIMD3<Float>(-tipDistance / 2, 0, 0))
        ))
        joints[.indexFingerTip] = .tracked(transform: MovementMath.worldTransform(
            anchor: wristTransform,
            joint: simd_float4x4(translation: SIMD3<Float>(tipDistance / 2, 0, 0))
        ))
        return .synthetic(hand: hand, timestamp: timestamp, joints: joints)
    }

    private static func sheepDropJointFrame(
        hand: AffectedHand,
        timestamp: TimeInterval,
        pose: SyntheticSheepDropPose,
        center: SIMD3<Float>
    ) -> HandJointFrame {
        var joints: [HandJoint: HandJointSample] = [
            .wrist: tracked(at: center + [0, -0.08, 0]),
            .indexFingerKnuckle: tracked(at: center + [-0.03, -0.02, 0]),
            .middleFingerKnuckle: tracked(at: center + [-0.01, -0.02, 0]),
            .ringFingerKnuckle: tracked(at: center + [0.01, -0.02, 0]),
            .littleFingerKnuckle: tracked(at: center + [0.03, -0.02, 0])
        ]
        let tipOffsets: [Float]
        switch pose {
        case .open:
            tipOffsets = [-0.05, -0.025, 0, 0.025, 0.05]
        case .clustered:
            tipOffsets = [-0.01, -0.005, 0, 0.005, 0.01]
        }
        let tips: [HandJoint] = [
            .thumbTip,
            .indexFingerTip,
            .middleFingerTip,
            .ringFingerTip,
            .littleFingerTip
        ]
        for (joint, offset) in zip(tips, tipOffsets) {
            joints[joint] = tracked(at: center + [offset, 0, 0])
        }
        return .synthetic(hand: hand, timestamp: timestamp, joints: joints)
    }

    private static func tracked(at position: SIMD3<Float>) -> HandJointSample {
        .tracked(transform: simd_float4x4(translation: position))
    }
}
