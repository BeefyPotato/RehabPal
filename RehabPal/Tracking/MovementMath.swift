import simd

enum MovementMath {
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
