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
    /// The hand anchor's world transform. This is deliberately distinct from
    /// the wrist joint transform: ARKit's anchor orientation is the reference
    /// project's source of palm rotation.
    let anchorTransform: simd_float4x4?

    init(hand: AffectedHand, timestamp: TimeInterval, joints: [HandJoint: HandJointSample], anchorTransform: simd_float4x4? = nil) {
        self.hand = hand
        self.timestamp = timestamp
        self.joints = joints
        self.anchorTransform = anchorTransform ?? joints[.wrist]?.transform
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
        joints: [HandJoint: HandJointSample],
        anchorTransform: simd_float4x4? = nil
    ) -> HandJointFrame {
        HandJointFrame(hand: hand, timestamp: timestamp, joints: joints, anchorTransform: anchorTransform)
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
        self.anchorTransform = anchor.originFromAnchorTransform
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

/// Exact calibration gate and anchor-relative rotation used by test8-2.
struct WristNeutralCalibration: Sendable {
    static let maximumLevelKnuckleHeightDelta: Float = 0.02
    static let requiredJoints: Set<HandJoint> = [
        .wrist,
        .indexFingerKnuckle,
        .middleFingerKnuckle,
        .ringFingerKnuckle,
        .littleFingerKnuckle
    ]

    let neutralAnchorOrientation: simd_quatf
    /// Compatibility datum for wrist diagnostic measurements. Balance never
    /// consumes this property; its neutral comes from the hand anchor.
    let wristTransform: simd_float4x4

    init?(wristTransform: simd_float4x4) {
        guard Self.isFinite(wristTransform.columns.0),
              Self.isFinite(wristTransform.columns.1),
              Self.isFinite(wristTransform.columns.2),
              Self.isFinite(wristTransform.columns.3) else {
            return nil
        }
        self.neutralAnchorOrientation = simd_quatf(wristTransform)
        self.wristTransform = wristTransform
    }

    private init?(anchorTransform: simd_float4x4, wristTransform: simd_float4x4) {
        guard Self.isFinite(anchorTransform), Self.isFinite(wristTransform) else { return nil }
        neutralAnchorOrientation = simd_quatf(anchorTransform)
        self.wristTransform = wristTransform
    }

    static func capture(from frame: HandJointFrame) -> WristNeutralCalibration? {
        guard frame.confidence(requiring: requiredJoints) == .good,
              let anchorTransform = frame.anchorTransform,
              requiredJoints.allSatisfy({ joint in
                  guard let transform = frame.joint(joint)?.transform else { return false }
                  return isFinite(transform)
              }) else {
            return nil
        }
        guard isReferencePose(frame) else { return nil }
        guard let wristTransform = frame.joint(.wrist)?.transform else { return nil }
        return WristNeutralCalibration(anchorTransform: anchorTransform, wristTransform: wristTransform)
    }

    func relativeRotation(for frame: HandJointFrame) -> simd_quatf? {
        guard let anchor = frame.anchorTransform else { return nil }
        return simd_normalize(simd_quatf(anchor) * neutralAnchorOrientation.inverse)
    }

    static func isReferencePose(_ frame: HandJointFrame) -> Bool {
        let ordered: [HandJoint] = [.indexFingerKnuckle, .middleFingerKnuckle, .ringFingerKnuckle, .littleFingerKnuckle]
        let points = ordered.compactMap { frame.joint($0)?.position }
        guard points.count == 4,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return false }
        let endpoint = points[3] - points[0]
        let span = simd_length(endpoint)
        guard span > 1e-4 else { return false }
        let axis = endpoint / span
        guard abs(axis.y) <= 0.25 else { return false }
        let ys = points.map(\.y)
        guard (ys.max()! - ys.min()!) <= 0.02 else { return false }
        func distanceToEndpointLine(_ point: SIMD3<Float>) -> Float {
            simd_length(simd_cross(point - points[0], axis))
        }
        return distanceToEndpointLine(points[1]) <= 0.012 &&
            distanceToEndpointLine(points[2]) <= 0.012
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
