import Foundation
import simd

struct DetectedTableSurface: Equatable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let transform: simd_float4x4
    let extent: SIMD2<Float>
    let isTracked: Bool
}

enum TableSurfaceUpdate: Sendable {
    case added(DetectedTableSurface)
    case updated(DetectedTableSurface)
    case removed(id: UUID, timestamp: TimeInterval)
}

struct TablePlacement: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case detected
        case estimated
    }

    let transform: simd_float4x4
    let source: Source

    static let estimatedReference = TablePlacement(
        transform: simd_float4x4(translation: [0, 0.73, -0.55]),
        source: .estimated
    )
}

struct TableSurfaceSelector: Sendable {
    private static let minimumHeight: Float = 0.60
    private static let maximumHeight: Float = 0.95
    private static let minimumExtent = SIMD2<Float>(1.0, 0.7)
    private static let stabilityDuration: TimeInterval = 0.35
    private static let timestampTolerance: TimeInterval = 1e-9
    private static let maximumHeightDrift: Float = 0.015
    private static let maximumNormalDrift = Float(5 * Double.pi / 180)
    private static let fallbackDelay: TimeInterval = 3

    private struct Candidate: Sendable {
        let baseline: DetectedTableSurface
        let stabilityStartedAt: TimeInterval
    }

    private let scanStartedAt: TimeInterval
    private var candidates: [UUID: Candidate] = [:]
    private var selectedSurface: DetectedTableSurface?
    private var currentPlacement: TablePlacement?
    private var isLocked = false

    init(scanStartedAt: TimeInterval) {
        self.scanStartedAt = scanStartedAt
    }

    mutating func receive(
        _ update: TableSurfaceUpdate,
        at timestamp: TimeInterval
    ) -> TablePlacement? {
        guard !isLocked else { return currentPlacement }

        switch update {
        case let .added(surface), let .updated(surface):
            receive(surface, at: timestamp)
        case let .removed(id, _):
            candidates[id] = nil
            if selectedSurface?.id == id {
                selectedSurface = nil
                currentPlacement = nil
            }
        }

        return placement(at: timestamp)
    }

    mutating func placement(at timestamp: TimeInterval) -> TablePlacement? {
        if let currentPlacement {
            return currentPlacement
        }
        guard timestamp.isFinite,
              scanStartedAt.isFinite,
              timestamp - scanStartedAt >= Self.fallbackDelay else {
            return nil
        }

        currentPlacement = .estimatedReference
        return currentPlacement
    }

    mutating func lock() {
        isLocked = currentPlacement != nil
    }

    private mutating func receive(
        _ surface: DetectedTableSurface,
        at timestamp: TimeInterval
    ) {
        guard Self.isSuitable(surface), timestamp.isFinite else {
            candidates[surface.id] = nil
            if selectedSurface?.id == surface.id {
                selectedSurface = nil
                currentPlacement = nil
            }
            return
        }

        if let selectedSurface {
            guard selectedSurface.id == surface.id else {
                return
            }
            guard Self.isCompatible(surface, with: selectedSurface) else {
                self.selectedSurface = nil
                currentPlacement = nil
                candidates[surface.id] = Candidate(
                    baseline: surface,
                    stabilityStartedAt: timestamp
                )
                return
            }
            self.selectedSurface = surface
            currentPlacement = TablePlacement(
                transform: surface.transform,
                source: .detected
            )
            return
        }

        guard let candidate = candidates[surface.id] else {
            candidates[surface.id] = Candidate(
                baseline: surface,
                stabilityStartedAt: timestamp
            )
            return
        }

        guard Self.isCompatible(surface, with: candidate.baseline) else {
            candidates[surface.id] = Candidate(
                baseline: surface,
                stabilityStartedAt: timestamp
            )
            return
        }

        guard timestamp - candidate.stabilityStartedAt + Self.timestampTolerance >=
                Self.stabilityDuration else {
            return
        }
        selectedSurface = surface
        currentPlacement = TablePlacement(
            transform: surface.transform,
            source: .detected
        )
    }

    private static func isSuitable(_ surface: DetectedTableSurface) -> Bool {
        let translation = surface.transform.translation
        return surface.isTracked &&
        surface.timestamp.isFinite &&
        translation.x.isFinite &&
        translation.y.isFinite &&
        translation.z.isFinite &&
        translation.y > minimumHeight &&
        translation.y < maximumHeight &&
        surface.extent.x.isFinite &&
        surface.extent.y.isFinite &&
        surface.extent.x >= minimumExtent.x &&
        surface.extent.y >= minimumExtent.y &&
        normal(of: surface.transform) != nil
    }

    private static func isCompatible(
        _ surface: DetectedTableSurface,
        with baseline: DetectedTableSurface
    ) -> Bool {
        guard abs(surface.transform.translation.y - baseline.transform.translation.y) <=
                maximumHeightDrift,
              let surfaceNormal = normal(of: surface.transform),
              let baselineNormal = normal(of: baseline.transform) else {
            return false
        }
        let cosine = simd_clamp(simd_dot(surfaceNormal, baselineNormal), -1, 1)
        return acos(cosine) <= maximumNormalDrift
    }

    private static func normal(
        of transform: simd_float4x4
    ) -> SIMD3<Float>? {
        let column = transform.columns.1
        let normal = SIMD3<Float>(column.x, column.y, column.z)
        let length = simd_length(normal)
        guard length.isFinite, length > 0 else { return nil }
        return normal / length
    }
}
