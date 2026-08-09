import simd

extension MovementObservation {
    /// Temporary compatibility projection for legacy processors. Its only
    /// input is the coordinator-accepted, app-owned joint frame.
    init(acceptedJointFrame frame: HandJointFrame) {
        guard let wristTransform = frame.joint(.wrist)?.transform else {
            self = .untracked(at: frame.timestamp)
            return
        }

        let forward = SIMD3<Float>(
            wristTransform.columns.2.x,
            wristTransform.columns.2.y,
            wristTransform.columns.2.z
        )
        let thumbToIndexDistance = Self.distance(
            frame,
            first: .thumbTip,
            second: .indexFingerTip
        )
        let closure = thumbToIndexDistance.map {
            min(max(1 - $0 / 0.09, 0), 1)
        } ?? 0
        let digits = Self.digitKinematics(from: frame)

        self.init(
            timestamp: frame.timestamp,
            isTracked: true,
            wristPitch: atan2(forward.y, max(0.0001, abs(forward.z))),
            wristRoll: atan2(forward.x, max(0.0001, abs(forward.z))),
            closure: closure,
            thumbToIndexDistance: thumbToIndexDistance,
            quality: digits.count == HandDigit.allCases.count ? .good : .low,
            digits: digits
        )
    }

    private static func digitKinematics(
        from frame: HandJointFrame
    ) -> [HandDigit: DigitKinematics] {
        let joints: [HandDigit: [HandJoint]] = [
            .thumb: [
                .thumbKnuckle,
                .thumbIntermediateBase,
                .thumbIntermediateTip,
                .thumbTip
            ],
            .index: [
                .indexFingerMetacarpal,
                .indexFingerKnuckle,
                .indexFingerIntermediateBase,
                .indexFingerIntermediateTip,
                .indexFingerTip
            ],
            .middle: [
                .middleFingerMetacarpal,
                .middleFingerKnuckle,
                .middleFingerIntermediateBase,
                .middleFingerIntermediateTip,
                .middleFingerTip
            ],
            .ring: [
                .ringFingerMetacarpal,
                .ringFingerKnuckle,
                .ringFingerIntermediateBase,
                .ringFingerIntermediateTip,
                .ringFingerTip
            ],
            .little: [
                .littleFingerMetacarpal,
                .littleFingerKnuckle,
                .littleFingerIntermediateBase,
                .littleFingerIntermediateTip,
                .littleFingerTip
            ]
        ]
        let littleTip = frame.joint(.littleFingerTip)?.position

        return Dictionary(uniqueKeysWithValues: joints.compactMap { digit, names in
            let points = names.compactMap { frame.joint($0)?.position }
            guard points.count == names.count else { return nil }
            let angles: [Float]
            if digit == .thumb {
                angles = [
                    Self.jointAngle(points[0], points[1], points[2]),
                    Self.jointAngle(points[1], points[2], points[3]),
                    0
                ]
            } else {
                angles = [
                    Self.jointAngle(points[0], points[1], points[2]),
                    Self.jointAngle(points[1], points[2], points[3]),
                    Self.jointAngle(points[2], points[3], points[4])
                ]
            }
            let opposition = digit == .thumb && littleTip != nil
                ? simd_distance(points.last!, littleTip!)
                : nil
            return (
                digit,
                DigitKinematics(
                    mcpAngle: angles[0],
                    pipAngle: angles[1],
                    dipAngle: angles[2],
                    oppositionDistance: opposition,
                    isTracked: true
                )
            )
        })
    }

    private static func distance(
        _ frame: HandJointFrame,
        first: HandJoint,
        second: HandJoint
    ) -> Float? {
        guard let first = frame.joint(first)?.position,
              let second = frame.joint(second)?.position else {
            return nil
        }
        return simd_distance(first, second)
    }

    private static func jointAngle(
        _ first: SIMD3<Float>,
        _ middle: SIMD3<Float>,
        _ last: SIMD3<Float>
    ) -> Float {
        MovementMath.angle(between: first - middle, and: last - middle) * 180 / .pi
    }
}
