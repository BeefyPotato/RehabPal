import Foundation
import simd

enum TrackingQuality: String, Equatable, Sendable {
    case unavailable
    case interrupted
    case low
    case good
}

struct MovementObservation: Equatable, Sendable {
    struct DigitKinematics: Equatable, Sendable {
        let mcpAngle: Float
        let pipAngle: Float
        let dipAngle: Float
        let oppositionDistance: Float?
        let isTracked: Bool
    }

    let timestamp: TimeInterval
    let isTracked: Bool
    let wristPitch: Float
    let wristRoll: Float
    let closure: Float
    let thumbToIndexDistance: Float?
    let quality: TrackingQuality
    let digits: [HandDigit: DigitKinematics]

    init(timestamp: TimeInterval, isTracked: Bool, wristPitch: Float, wristRoll: Float, closure: Float, thumbToIndexDistance: Float?, quality: TrackingQuality, digits: [HandDigit: DigitKinematics] = [:]) {
        self.timestamp = timestamp
        self.isTracked = isTracked
        self.wristPitch = wristPitch
        self.wristRoll = wristRoll
        self.closure = closure
        self.thumbToIndexDistance = thumbToIndexDistance
        self.quality = quality
        self.digits = digits
    }

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
    var latestJointFrame: HandJointFrame? { get }
    var isFallback: Bool { get }
}
