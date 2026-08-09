import simd

enum MovementMath {
    nonisolated static let maximumWristTilt: Float = .pi / 9

    nonisolated static func angle(between lhs: SIMD3<Float>, and rhs: SIMD3<Float>) -> Float {
        let denominator = simd_length(lhs) * simd_length(rhs)
        guard denominator > .ulpOfOne else { return 0 }
        return acos(simd_clamp(simd_dot(lhs, rhs) / denominator, -1, 1))
    }

    nonisolated static func worldTransform(
        anchor: simd_float4x4,
        joint: simd_float4x4
    ) -> simd_float4x4 {
        simd_mul(anchor, joint)
    }

    nonisolated static func relativeTransform(
        reference: simd_float4x4,
        current: simd_float4x4
    ) -> simd_float4x4 {
        simd_mul(simd_inverse(reference), current)
    }

    /// Returns calibrated wrist pitch and roll, with world-y yaw removed before
    /// extracting the two tray-control axes.
    nonisolated static func wristTilt(relativeTransform: simd_float4x4) -> WristTilt {
        let yaw = atan2(relativeTransform.columns.2.x, relativeTransform.columns.2.z)
        let withoutYaw = simd_mul(yawRotation(-yaw), relativeTransform)
        let pitch = asin(simd_clamp(-withoutYaw.columns.2.y, -1, 1))
        let roll = atan2(withoutYaw.columns.0.y, withoutYaw.columns.1.y)
        return WristTilt(
            pitch: simd_clamp(pitch, -maximumWristTilt, maximumWristTilt),
            roll: simd_clamp(roll, -maximumWristTilt, maximumWristTilt)
        )
    }

    /// Compares yaw-free world orientations so a world-y rotation remains yaw
    /// even when the neutral pose itself was pitched or rolled.
    nonisolated static func wristTilt(
        reference: simd_float4x4,
        current: simd_float4x4
    ) -> WristTilt {
        wristTilt(relativeTransform: relativeTransform(
            reference: removingWorldYaw(reference),
            current: removingWorldYaw(current)
        ))
    }

    nonisolated static func wristTransform(pitch: Float, roll: Float, yaw: Float = 0) -> simd_float4x4 {
        let pitchRotation = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(pitch), sin(pitch), 0),
            SIMD4<Float>(0, -sin(pitch), cos(pitch), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        let rollRotation = simd_float4x4(columns: (
            SIMD4<Float>(cos(roll), sin(roll), 0, 0),
            SIMD4<Float>(-sin(roll), cos(roll), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        return simd_mul(yawRotation(yaw), simd_mul(pitchRotation, rollRotation))
    }

    private nonisolated static func yawRotation(_ angle: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(cos(angle), 0, -sin(angle), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sin(angle), 0, cos(angle), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    private nonisolated static func removingWorldYaw(_ transform: simd_float4x4) -> simd_float4x4 {
        let yaw = atan2(transform.columns.2.x, transform.columns.2.z)
        return simd_mul(yawRotation(-yaw), transform)
    }
}

struct WristTilt: Equatable, Sendable {
    let pitch: Float
    let roll: Float
}

extension simd_float4x4 {
    nonisolated init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation, 1)
    }

    nonisolated var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
