import ARKit
import Observation
import simd

@MainActor
@Observable
final class HandTrackingEngine: MovementObservationSource {
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private(set) var latestObservation = MovementObservation.untracked(at: 0)
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
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
            latestObservation = .untracked(at: timestamp)
            return
        }

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

        latestObservation = MovementObservation(
            timestamp: timestamp,
            isTracked: true,
            wristPitch: pitch,
            wristRoll: roll,
            closure: closure,
            thumbToIndexDistance: distance,
            quality: .good
        )
    }
}
