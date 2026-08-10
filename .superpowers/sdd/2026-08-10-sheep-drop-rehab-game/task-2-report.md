# Task 2 Report: App-Owned Table Detection

## Status

Implemented and ready to commit as `Add shared table surface tracking`.
The immutable table model and selector contain no ARKit types; the shared
engine remains the sole ARKit session owner.

## Files changed

- `RehabPal/Tracking/TableSurface.swift`
  - Added app-owned surface updates and placements.
  - Added pure first-stable selection, strict height/extent filtering,
    stability drift limits, three-second fallback, removal handling, and
    placement locking.
- `RehabPal/Tracking/HandTrackingEngine.swift`
  - Added horizontal plane detection to the existing hand/world session run.
  - Converts plane anchors immediately into app-owned values.
  - Generation-keys plane consumption and fallback publication, and clears
    table state on stop/start invalidation.
- `RehabPal/Session/RehabSessionContracts.swift`
  - Owns the live-session protocol and its default-nil `tablePlacement` API.
- `RehabPal/Session/RehabSessionCoordinator.swift`
  - Exposes live Sheep Drop placement and the deterministic Demo Mode
    estimated reference placement only while the session is active.
- `RehabPalTests/TableSurfaceTests.swift`
  - Exercises the real pure selector across all specified thresholds,
    fallback, removal, tracking loss, first-stable choice, and locking.
- `RehabPalTests/HandTrackingEngineTests.swift`
  - Covers one shared start boundary, stop clearing, and stale-generation
    plane update rejection through an external-update seam.
- `RehabPalTests/RehabSessionCoordinatorTests.swift`
  - Covers live publication/cancel invalidation and ARKit-free Demo Mode.

## RED evidence

Pure selector command:

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/TableSurfaceTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask2SelectorRed \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `65`, as expected, because `DetectedTableSurface` and
`TableSurfaceSelector` did not exist.

Integration command:

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/HandTrackingEngineTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask2IntegrationRedFixed \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `65`, as expected, because the engine plane-update initializer
and live-session table API were absent.

The final tracking-loss mutation test was also observed RED with
`test-without-building` (exit `65`): the selected placement remained present
after an untracked update.

## GREEN evidence

Required generic visionOS command:

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/TableSurfaceTests \
  -only-testing:RehabPalTests/HandTrackingEngineTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask2FinalGreen \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`, with no compiler warnings.

Runtime command:

```bash
xcodebuild test -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'platform=visionOS Simulator,id=2005850E-20C9-4441-B27B-1F665EFB1164' \
  -parallel-testing-enabled NO \
  -only-testing:RehabPalTests/TableSurfaceTests \
  -only-testing:RehabPalTests/HandTrackingEngineTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask2RuntimeGreen \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`. All three suites executed successfully with no runtime
warnings. The focused tracking-loss GREEN run also exited `0`.

## Self-review

- Confirmed there is still one `ARKitSession`, with hand, world, and
  horizontal plane providers passed to one `session.run` call.
- Confirmed every plane task and fallback publication checks the active
  startup generation, while existing hand demultiplexing and session-event
  semantics remain unchanged.
- Confirmed `PlaneAnchor` and `AnchorUpdate` are confined to
  `HandTrackingEngine`; selector, coordinator, and game-facing contracts use
  app-owned values only.
- Confirmed strict 0.60/0.95 m exclusion, 1.0 x 0.7 m minimum extent,
  0.35-second stability, 1.5 cm height drift, 5-degree normal drift, and
  three-second fallback behavior.
- Confirmed cancellation, failure, completion, stop, and superseded starts
  cannot expose stale placement through the coordinator.
- Ran the mutation check, final targeted build, runtime tests, and
  `git diff --check` before commit.

## Concerns

- Parallel visionOS simulator clones hung while finalizing Xcode diagnostics;
  disabling parallel testing produced repeatable exit-0 runtime runs. This is
  a simulator tooling issue, not a test or app failure.
- Xcode 27 plane anchors do not expose `isTracked`; added/updated anchors map
  to `isTracked: true`, and the provider's removed event is the loss signal.
  The pure/injected boundary still accepts and tests explicit untracked input.
