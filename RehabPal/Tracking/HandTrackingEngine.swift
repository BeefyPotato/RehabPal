import ARKit
import Observation
import simd

@MainActor
@Observable
final class HandTrackingEngine: MovementObservationSource {
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private(set) var latestObservation = MovementObservation.untracked(at: 0)
    private(set) var latestJointFrame: HandJointFrame?
    private(set) var lastError: String?
    let isFallback = false

    var isSupported: Bool { HandTrackingProvider.isSupported }

    func start() async {
        guard isSupported else {
            lastError = "Hand tracking is unavailable in this environment."
            return
        }
        do {
            try await session.run([provider])
            for await update in provider.anchorUpdates {
                consume(update.anchor)
            }
        } catch {
            lastError = "Hand tracking could not start: \(error.localizedDescription)"
        }
    }

    private func consume(_ anchor: HandAnchor) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let frame = HandJointFrame(anchor: anchor, timestamp: timestamp),
              let skeleton = anchor.handSkeleton else {
            latestJointFrame = nil
            latestObservation = .untracked(at: timestamp)
            return
        }
        latestJointFrame = frame

        let wrist = skeleton.joint(.wrist)
        let indexTip = skeleton.joint(.indexFingerTip)
        let thumbTip = skeleton.joint(.thumbTip)
        guard wrist.isTracked, indexTip.isTracked, thumbTip.isTracked else {
            latestObservation = .untracked(at: timestamp)
            return
        }

        let wristWorld = MovementMath.worldTransform(
            anchor: anchor.originFromAnchorTransform,
            joint: wrist.anchorFromJointTransform
        )
        let indexWorld = MovementMath.worldTransform(
            anchor: anchor.originFromAnchorTransform,
            joint: indexTip.anchorFromJointTransform
        )
        let thumbWorld = MovementMath.worldTransform(
            anchor: anchor.originFromAnchorTransform,
            joint: thumbTip.anchorFromJointTransform
        )
        let distance = simd_distance(indexWorld.translation, thumbWorld.translation)
        let closure = min(max(1 - distance / 0.09, 0), 1)
        let forward = SIMD3<Float>(wristWorld.columns.2.x, wristWorld.columns.2.y, wristWorld.columns.2.z)
        let pitch = atan2(forward.y, max(0.0001, abs(forward.z)))
        let roll = atan2(forward.x, max(0.0001, abs(forward.z)))
        let digits = digitKinematics(from: skeleton, anchorTransform: anchor.originFromAnchorTransform)

        latestObservation = MovementObservation(
            timestamp: timestamp,
            isTracked: true,
            wristPitch: pitch,
            wristRoll: roll,
            closure: closure,
            thumbToIndexDistance: distance,
            quality: digits.count == HandDigit.allCases.count ? .good : .low,
            digits: digits
        )
    }

    private func digitKinematics(from skeleton: HandSkeleton, anchorTransform: simd_float4x4) -> [HandDigit: MovementObservation.DigitKinematics] {
        let names: [HandDigit: [HandSkeleton.JointName]] = [
            .thumb: [.thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip],
            .index: [.indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip],
            .middle: [.middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip],
            .ring: [.ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip],
            .little: [.littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip]
        ]
        let littleTip = skeleton.joint(.littleFingerTip)
        let littlePosition = littleTip.isTracked ? worldPosition(littleTip, anchorTransform: anchorTransform) : nil
        return Dictionary(uniqueKeysWithValues: names.compactMap { digit, jointNames in
            let joints = jointNames.map { skeleton.joint($0) }
            guard joints.allSatisfy(\.isTracked) else { return nil }
            let points = joints.map { worldPosition($0, anchorTransform: anchorTransform) }
            let angles: [Float]
            if digit == .thumb {
                angles = [jointAngle(points[0], points[1], points[2]), jointAngle(points[1], points[2], points[3]), 0]
            } else {
                angles = [jointAngle(points[0], points[1], points[2]), jointAngle(points[1], points[2], points[3]), jointAngle(points[2], points[3], points[4])]
            }
            let opposition = digit == .thumb && littlePosition != nil ? simd_distance(points.last!, littlePosition!) : nil
            return (digit, MovementObservation.DigitKinematics(mcpAngle: angles[0], pipAngle: angles[1], dipAngle: angles[2], oppositionDistance: opposition, isTracked: true))
        })
    }

    private func worldPosition(_ joint: HandSkeleton.Joint, anchorTransform: simd_float4x4) -> SIMD3<Float> {
        MovementMath.worldTransform(anchor: anchorTransform, joint: joint.anchorFromJointTransform).translation
    }

    private func jointAngle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float {
        MovementMath.angle(between: a - b, and: c - b) * 180 / .pi
    }
}
