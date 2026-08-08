import Foundation
import Observation

@MainActor
@Observable
final class SyntheticMovementSource: MovementObservationSource {
    private(set) var latestObservation = MovementObservation(
        timestamp: 0,
        isTracked: true,
        wristPitch: 0,
        wristRoll: 0,
        closure: 0,
        thumbToIndexDistance: 0.08,
        quality: .good
    )
    let isFallback = true

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
    }
}
