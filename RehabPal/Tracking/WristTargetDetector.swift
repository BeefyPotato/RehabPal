import Foundation

enum WristDirection: String, CaseIterable, Equatable, Sendable {
    case forward
    case backward
    case left
    case right
}

struct WristTargetDetector: Sendable {
    let targetMagnitude: Float
    let tolerance: Float

    nonisolated func classify(pitch: Float, roll: Float) -> WristDirection? {
        let dominant: (magnitude: Float, direction: WristDirection)
        if abs(pitch) >= abs(roll) {
            dominant = (abs(pitch), pitch >= 0 ? .forward : .backward)
        } else {
            dominant = (abs(roll), roll >= 0 ? .right : .left)
        }
        guard abs(dominant.magnitude - targetMagnitude) <= tolerance else { return nil }
        return dominant.direction
    }
}
