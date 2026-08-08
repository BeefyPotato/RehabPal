import Foundation
import simd

enum TrackingQuality: String, Equatable, Sendable {
    case unavailable
    case interrupted
    case low
    case good
}

struct MovementObservation: Equatable, Sendable {
    let timestamp: TimeInterval
    let isTracked: Bool
    let wristPitch: Float
    let wristRoll: Float
    let closure: Float
    let thumbToIndexDistance: Float?
    let quality: TrackingQuality

    static func untracked(at timestamp: TimeInterval) -> MovementObservation {
        MovementObservation(
            timestamp: timestamp,
            isTracked: false,
            wristPitch: 0,
            wristRoll: 0,
            closure: 0,
            thumbToIndexDistance: nil,
            quality: .interrupted
        )
    }
}

protocol MovementObservationSource: AnyObject {
    var latestObservation: MovementObservation { get }
    var isFallback: Bool { get }
}
