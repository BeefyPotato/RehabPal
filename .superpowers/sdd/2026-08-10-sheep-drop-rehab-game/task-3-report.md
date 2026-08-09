# Task 3 Report: Five-Fingertip Sheep Drop Processor

## Status

Implemented the pure `SheepDropSession` processor and its focused tests. The
processor imports only Foundation and SIMD; it contains no RealityKit or ARKit
types.

## Files changed

- `RehabPal/Features/SheepDrop/SheepDropSession.swift`
  - Added five-tip pose extraction, median hand-scale normalization, maximum
    pairwise separation, affected-hand filtering, monotonic dwell gates,
    pickup/carry/release hysteresis, offset-preserving exponential smoothing,
    safe-volume clamping, tracking-loss commands, explicit-release scoring,
    deterministic success/reset deadlines, progress, and result provenance.
- `RehabPalTests/SheepDropSessionTests.swift`
  - Added 27 mutation-named tests against real processor behavior.
- `RehabPalTests/JointFrameTests.swift`
  - Unchanged; the Sheep Drop-specific synthetic frame helper remains local to
    `SheepDropSessionTests`.

## RED evidence

Pose extraction RED:

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/SheepDropSessionTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask3PoseRed \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `65`, specifically because `FiveFingertipPose` did not exist.

Pickup/carry/release RED used the same focused command with derived data
`RehabPalSheepTask3CarryRed`. Result: exit `65`, specifically because
`SheepDropObservation` and the processor state API did not exist.

Scoring/reset/result RED used derived data
`RehabPalSheepTask3ScoreRedCorrected`. Result: exit `65`, specifically because
the placement, reset, success-deadline, and completion events did not exist.

Runtime RED exposed a real repeated-cycle defect after the scoring code first
compiled:

```bash
xcodebuild test-without-building -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'platform=visionOS Simulator,id=2005850E-20C9-4441-B27B-1F665EFB1164' \
  -parallel-testing-enabled NO \
  -only-testing:RehabPalTests/SheepDropSessionTests/testFiveSuccessfulDropsCreateSheepDropGameplayResult \
  -derivedDataPath /private/tmp/RehabPalSheepTask3RuntimeSmoke \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `65`. Later-cycle `0.15`-second releases could be one floating-point
ulp below the boundary. A `1e-9`-second comparison tolerance fixed timestamps
without changing the prescribed durations.

The final lifecycle mutations were also observed RED with the simulator:
settled dwell survived a pause, and a post-completion frame emitted `falling`.
The focused two-test run exited `65` before the minimal fixes.

## GREEN evidence

Focused serial simulator execution:

```bash
xcodebuild test-without-building -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'platform=visionOS Simulator,id=2005850E-20C9-4441-B27B-1F665EFB1164' \
  -parallel-testing-enabled NO \
  -only-testing:RehabPalTests/SheepDropSessionTests \
  -only-testing:RehabPalTests/JointFrameTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask3FinalRuntime \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`; 41 tests executed, 0 failures (27 Sheep Drop tests and 14
Joint Frame tests).

Focused generic test build:

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/SheepDropSessionTests \
  -only-testing:RehabPalTests/JointFrameTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask3FinalGenericTests \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`, with no compiler warnings.

Generic app build:

```bash
xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalSheepTask3FinalApp \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`, with no compiler warnings.

## Self-review

- Confirmed the required set is wrist, four knuckles, and all five tips.
- Confirmed scale is the median wrist-to-knuckle distance in metres, valid only
  from 0.04 through 0.14 m, and tip clustering uses maximum pairwise distance.
- Confirmed pickup and release use continuous 0.25/0.15-second monotonic dwells,
  with `0.62` pickup and `0.95` release thresholds providing hysteresis.
- Confirmed the sheep-to-centroid offset is captured once and centroid filtering
  uses `alpha = 1 - exp(-dt / 0.08)` before radial/vertical clamping.
- Confirmed missing tracking freezes carrying and never becomes release; pause
  clears grasp, release, and settled dwell while preserving completed drops.
- Confirmed scoring requires explicit release plus inner-pen, 2.5-radius height,
  0.08 m/s speed, and 0.25-second settled gates.
- Confirmed success changes phase before increment exposure, preventing duplicate
  scores, and all reset commands set linear and angular velocities to zero.
- Confirmed progress includes grasp partial only before pickup, and result notes
  distinguish live five-fingertip observations from simulated joint observations.
- Confirmed no RealityKit or ARKit symbol occurs in the processor.

## Concerns

- Positions are intentionally pen-local: the processor assumes scene/table
  center at horizontal origin and table/floor height at `y = 0`. The Task 5 view
  must convert world/entity coordinates to that contract before processing.
- One exploratory simulator command that combined disabled parallel testing
  with an extra maximum-worker flag hung during Xcode result finalization. The
  canonical serial commands without that extra flag completed repeatably at
  exit `0`; this was a tooling teardown issue, not a processor failure.
- Physical hand comfort and RealityKit physics remain Task 5/device acceptance
  work and are not inferred from these pure processor tests.
