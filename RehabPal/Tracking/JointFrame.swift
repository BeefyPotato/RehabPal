import ARKit
import Foundation
import simd

/// The stable joint vocabulary consumed by RehabPal processors.
///
/// ARKit joint names are intentionally translated at the tracking boundary so
/// exercise code never needs to depend on `HandSkeleton`.
enum HandJoint: String, CaseIterable, Hashable, Sendable {
    case wrist
    case thumbKnuckle
    case thumbIntermediateBase
    case thumbIntermediateTip
    case thumbTip
    case indexFingerMetacarpal
    case indexFingerKnuckle
    case indexFingerIntermediateBase
    case indexFingerIntermediateTip
    case indexFingerTip
    case middleFingerMetacarpal
    case middleFingerKnuckle
    case middleFingerIntermediateBase
    case middleFingerIntermediateTip
    case middleFingerTip
    case ringFingerMetacarpal
    case ringFingerKnuckle
    case ringFingerIntermediateBase
    case ringFingerIntermediateTip
    case ringFingerTip
    case littleFingerMetacarpal
    case littleFingerKnuckle
    case littleFingerIntermediateBase
    case littleFingerIntermediateTip
    case littleFingerTip

    fileprivate var arKitJointName: HandSkeleton.JointName {
        switch self {
        case .wrist: .wrist
        case .thumbKnuckle: .thumbKnuckle
        case .thumbIntermediateBase: .thumbIntermediateBase
        case .thumbIntermediateTip: .thumbIntermediateTip
        case .thumbTip: .thumbTip
        case .indexFingerMetacarpal: .indexFingerMetacarpal
        case .indexFingerKnuckle: .indexFingerKnuckle
        case .indexFingerIntermediateBase: .indexFingerIntermediateBase
        case .indexFingerIntermediateTip: .indexFingerIntermediateTip
        case .indexFingerTip: .indexFingerTip
        case .middleFingerMetacarpal: .middleFingerMetacarpal
        case .middleFingerKnuckle: .middleFingerKnuckle
        case .middleFingerIntermediateBase: .middleFingerIntermediateBase
        case .middleFingerIntermediateTip: .middleFingerIntermediateTip
        case .middleFingerTip: .middleFingerTip
        case .ringFingerMetacarpal: .ringFingerMetacarpal
        case .ringFingerKnuckle: .ringFingerKnuckle
        case .ringFingerIntermediateBase: .ringFingerIntermediateBase
        case .ringFingerIntermediateTip: .ringFingerIntermediateTip
        case .ringFingerTip: .ringFingerTip
        case .littleFingerMetacarpal: .littleFingerMetacarpal
        case .littleFingerKnuckle: .littleFingerKnuckle
        case .littleFingerIntermediateBase: .littleFingerIntermediateBase
        case .littleFingerIntermediateTip: .littleFingerIntermediateTip
        case .littleFingerTip: .littleFingerTip
        }
    }
}

/// A single app-owned joint observation. A transform is present only when the
/// ARKit joint was tracked in this frame.
enum HandJointSample: Sendable {
    case tracked(transform: simd_float4x4)
    case untracked

    var transform: simd_float4x4? {
        guard case let .tracked(transform) = self else { return nil }
        return transform
    }

    var position: SIMD3<Float>? {
        transform?.translation
    }

    var isTracked: Bool {
        transform != nil
    }
}

/// An immutable, world-space hand snapshot. It carries no ARKit model types.
struct HandJointFrame: Sendable {
    let hand: AffectedHand
    let timestamp: TimeInterval
    let joints: [HandJoint: HandJointSample]

    init(hand: AffectedHand, timestamp: TimeInterval, joints: [HandJoint: HandJointSample]) {
        self.hand = hand
        self.timestamp = timestamp
        self.joints = joints
    }

    func joint(_ joint: HandJoint) -> HandJointSample? {
        joints[joint]
    }

    func isForAffectedHand(_ affectedHand: AffectedHand) -> Bool {
        hand == affectedHand
    }

    func confidence(requiring requiredJoints: Set<HandJoint>) -> TrackingQuality {
        guard !requiredJoints.isEmpty else { return .unavailable }
        let trackedCount = requiredJoints.reduce(into: 0) { count, joint in
            if joints[joint]?.isTracked == true {
                count += 1
            }
        }
        guard trackedCount > 0 else { return .unavailable }
        return trackedCount == requiredJoints.count ? .good : .low
    }

    static func synthetic(
        hand: AffectedHand,
        timestamp: TimeInterval,
        joints: [HandJoint: HandJointSample]
    ) -> HandJointFrame {
        HandJointFrame(hand: hand, timestamp: timestamp, joints: joints)
    }

    init?(anchor: HandAnchor, timestamp: TimeInterval) {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return nil }
        switch anchor.chirality {
        case .left:
            hand = .left
        case .right:
            hand = .right
        @unknown default:
            return nil
        }
        self.timestamp = timestamp
        self.joints = Dictionary(uniqueKeysWithValues: HandJoint.allCases.map { joint in
            let arKitJoint = skeleton.joint(joint.arKitJointName)
            let sample: HandJointSample
            if arKitJoint.isTracked {
                sample = .tracked(transform: MovementMath.worldTransform(
                    anchor: anchor.originFromAnchorTransform,
                    joint: arKitJoint.anchorFromJointTransform
                ))
            } else {
                sample = .untracked
            }
            return (joint, sample)
        })
    }
}

/// A coordinator-published tracking poll. Its sequence lets consumers process
/// a present or missing frame once even when RealityKit renders it repeatedly.
struct HandJointFrameObservation: Sendable {
    let sequence: Int
    let timestamp: TimeInterval
    let frame: HandJointFrame?
}

/// App-owned projection of ARKit's added/updated/removed hand-anchor stream.
/// Each chirality has an independent slot so an interleaved update or removal
/// from one hand can never erase the other hand's latest frame.
enum HandJointFrameUpdate: Sendable {
    case added(HandJointFrame)
    case updated(HandJointFrame)
    case removed(hand: AffectedHand, timestamp: TimeInterval)
}

struct HandJointFrameDemultiplexer: Sendable {
    private var frames: [AffectedHand: HandJointFrame] = [:]

    mutating func apply(_ update: HandJointFrameUpdate) {
        switch update {
        case let .added(frame), let .updated(frame):
            frames[frame.hand] = frame
        case let .removed(hand, _):
            frames[hand] = nil
        }
    }

    func frame(for hand: AffectedHand) -> HandJointFrame? {
        frames[hand]
    }

    mutating func removeAll() {
        frames.removeAll(keepingCapacity: true)
    }
}

/// Captures the tracked wrist orientation only when the wrist and all four
/// level knuckles are present, preventing a partial hand from becoming neutral.
struct WristNeutralCalibration: Sendable {
    static let maximumLevelKnuckleHeightDelta: Float = 0.01
    static let requiredJoints: Set<HandJoint> = [
        .wrist,
        .indexFingerKnuckle,
        .middleFingerKnuckle,
        .ringFingerKnuckle,
        .littleFingerKnuckle
    ]

    let wristTransform: simd_float4x4

    init?(wristTransform: simd_float4x4) {
        guard Self.isFinite(wristTransform.columns.0),
              Self.isFinite(wristTransform.columns.1),
              Self.isFinite(wristTransform.columns.2),
              Self.isFinite(wristTransform.columns.3) else {
            return nil
        }
        self.wristTransform = wristTransform
    }

    static func capture(from frame: HandJointFrame) -> WristNeutralCalibration? {
        guard frame.confidence(requiring: requiredJoints) == .good,
              let wristTransform = frame.joint(.wrist)?.transform,
              requiredJoints.allSatisfy({ joint in
                  guard let transform = frame.joint(joint)?.transform else { return false }
                  return isFinite(transform)
              }) else {
            return nil
        }
        let heights = levelKnuckles.compactMap { frame.joint($0)?.position?.y }
        guard let minimumHeight = heights.min(), let maximumHeight = heights.max(),
              maximumHeight - minimumHeight <= maximumLevelKnuckleHeightDelta else {
            return nil
        }
        return WristNeutralCalibration(wristTransform: wristTransform)
    }

    func tilt(for wristTransform: simd_float4x4) -> WristTilt {
        MovementMath.wristTilt(
            reference: self.wristTransform,
            current: wristTransform
        )
    }

    private static func isFinite(_ vector: SIMD4<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite && vector.w.isFinite
    }

    private static func isFinite(_ transform: simd_float4x4) -> Bool {
        isFinite(transform.columns.0) &&
        isFinite(transform.columns.1) &&
        isFinite(transform.columns.2) &&
        isFinite(transform.columns.3)
    }

    private static let levelKnuckles: Set<HandJoint> = [
        .indexFingerKnuckle,
        .middleFingerKnuckle,
        .ringFingerKnuckle,
        .littleFingerKnuckle
    ]
}
