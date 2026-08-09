import Foundation
import Observation
import simd

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
}
