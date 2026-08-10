# Task 3 Report: Viewer-Relative Locked Platform Placement

## Scope

Implemented Task 3 only in:

- `RehabPal/Features/Balance/BalancePlatformView.swift`
- `RehabPalTests/ExerciseSessionTests.swift`
- this report

No Sheep Drop, Squeeze, recovery UI, coordinator, or Task 4 frame-processing behavior changed.

## Implemented Behavior

- `BalancePlatformPlacement.position(viewerPosition:)` uses X `0`, Z `-1`, and viewer Y minus `0.25` metres clamped to `0.72...1.20` metres.
- A missing viewer position uses the exact fallback `(0, 0.9, -1)`.
- `BalancePlatformPlacementLatch` accepts the first computed position and ignores every later viewer pose.
- `BalancePlatformView` reads `coordinator.currentViewerPosition` once in RealityView scene construction and locks the result.
- Initial tray placement, tilt transforms, ball escape distance, and HUD placement all consume that locked tray position.
- The HUD preserves its former readable relative offset `(0, 0.28, 0.1)` from the tray instead of using an independent fixed world coordinate.
- No update/render path reads viewer position, so the scene never follows later head movement.

## TDD Evidence

RED was witnessed with the two mutation-named placement tests present before production changes. Generic visionOS `build-for-testing` failed with:

```text
cannot find 'BalancePlatformPlacement' in scope
cannot find 'BalancePlatformPlacementLatch' in scope
** TEST BUILD FAILED **
Exit: 65
```

The tests cover all literal height cases from the plan and prove a later valid pose and later missing pose cannot replace the first lock.

## Verification

Focused simulator run:

```text
xcodebuild test -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'platform=visionOS Simulator,id=2005850E-20C9-4441-B27B-1F665EFB1164' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 20 \
  -collect-test-diagnostics never \
  -only-testing:RehabPalTests/ExerciseSessionTests/testBalancePlatformPlacementUsesViewerHeightWithinSafetyBounds \
  -only-testing:RehabPalTests/ExerciseSessionTests/testBalancePlatformPlacementLatchKeepsTheFirstViewerPose \
  CODE_SIGNING_ALLOWED=NO
Exit: 0
Xcode test duration: 35.105 seconds
```

Generic test-bundle compile:

```text
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalBalanceTask3Green \
  CODE_SIGNING_ALLOWED=NO
Exit: 0
```

Generic app build:

```text
xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalBalanceTask3App \
  CODE_SIGNING_ALLOWED=NO
Exit: 0
```

`git diff --check` exited 0. Diff inspection confirmed the change is limited to the Balance view, focused tests, and this report.

## Remaining Physical Acceptance

The exact math and non-following latch are covered by automated tests. Comfortable perceived height and HUD readability still require the planned physical Vision Pro acceptance pass.
