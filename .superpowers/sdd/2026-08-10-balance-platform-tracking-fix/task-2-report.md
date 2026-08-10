# Task 2 Report: Balance Neutral Calibration and Dynamic Joint Requirements

## Scope

Implemented Task 2 on base commit `0325661d8bf37109f556ea9e1ae7a6e9fc42fb83`.

Changed only:

- `RehabPal/Features/Balance/BalanceSession.swift`
- `RehabPalTests/ExerciseSessionTests.swift`
- this report

No RealityKit view, coordinator, hand-tracking engine, yaw-removal, or tilt-clamp code changed. `JointFrame.swift` did not require modification because `WristNeutralCalibration.capture(from:)` already provides the full finite, tracked, level-pose predicate.

## Implemented Behavior

- Calibration requires exactly 25 unique, consecutive, valid affected-hand frames.
- Valid duplicate timestamps are ignored without incrementing progress.
- Missing frames, wrong-hand frames, invalid calibration poses, regressed timestamps, and nonfinite timestamps reset calibration progress.
- Frames 1–24 return `waitingForCalibration`; frame 25 supplies the captured wrist neutral.
- `calibrationFrameGoal` is 25 and `calibrationProgress` remains 25 while calibrated.
- `requiredJoints` is `WristNeutralCalibration.requiredJoints` before calibration and wrist-only afterward.
- Post-calibration missing knuckles do not pause active wrist tracking; a missing wrist does pause it.
- Brief loss retains calibration and requests a ball reset on recovery.
- Long loss clears neutral, timestamp history, and calibration progress; recovery requires 25 new valid frames.
- Completed target progress survives both tracking-loss paths.
- Existing relative tilt, yaw removal, and independent pitch/roll clamps are unchanged.

## TDD Evidence

RED was observed twice:

1. The chronology tests first failed to compile because `calibrationFrameGoal` and `calibrationProgress` did not exist. After adding only those interfaces, the single boundary test executed and failed with 51 expected assertions: the first frame returned `active`, progress stayed zero, and frame 25 used the original frame as neutral.
2. The phase-specific test failed to compile because `BalanceSession.requiredJoints` did not exist.

GREEN chronology run:

```text
xcodebuild test -quiet ...
  -parallel-testing-enabled NO
  -maximum-parallel-testing-workers 1
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 20
  [7 Task 2 chronology tests]
Exit: 0
```

The seven runtime-green tests cover the 25-frame boundary/capture, duplicate timestamps, missing frames, wrong hand, invalid pose, regressed timestamps, and NaN/positive-infinity/negative-infinity timestamps.

## Final Verification

Focused generic test-bundle compile:

```text
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/ExerciseSessionTests \
  -only-testing:RehabPalTests/JointFrameTests \
  -derivedDataPath /private/tmp/RehabPalBalanceTask2FocusedBuild \
  CODE_SIGNING_ALLOWED=NO
Exit: 0
```

Generic app build:

```text
xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalBalanceTask2App \
  CODE_SIGNING_ALLOWED=NO
Exit: 0
```

`git diff --check` exited 0.

## Environmental Limitation

A later bounded run of the complete `ExerciseSessionTests` target reached its 90-second process limit after Xcode 27 became stuck finalizing the simulator test log and launched a 600-second `simctl diagnose`. The partial `.xcresult` had no `Info.plist`, so no broader runtime result is claimed. This was treated as an environment/test-runner finalization issue rather than a passing or failing suite. The earlier bounded, serial seven-test chronology run completed normally with exit 0, and all final Task 2 tests compile in the focused generic test bundle.

## Fix Round 1

Review findings 1 and 2 were addressed with tests written before each production change:

- `testBalanceBriefPauseClearsPartialCalibrationProgressAndTimestamp` catches preservation of an unfinished calibration streak across `pause(requiresRecalibration: false)`. Brief pause now resets partial progress and timestamp history only while uncalibrated; an established neutral is still retained.
- `testBalanceInvalidDuplicateResetsProgressBeforeDuplicateSuppression` catches equality suppression running before pose validation. The existing neutral-pose capture predicate now validates first, so an invalid duplicate resets progress while an existing valid-duplicate test continues to require no increment.

The attempted single-test simulator RED invocation encountered the same Xcode runner/finalization hang and was terminated. Further simulator attempts were stopped by task direction; runtime execution of these two fix-round tests is therefore **UNVERIFIED** and is not represented as green. Their reviewed pre-fix failure paths are direct: the first path left `calibrationProgress == 10` after brief pause, and the second returned on timestamp equality before reaching capture validation.

Fresh deterministic verification after both fixes:

```text
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/ExerciseSessionTests \
  -only-testing:RehabPalTests/JointFrameTests \
  -derivedDataPath /private/tmp/RehabPalBalanceTask2Fix1FocusedBuild \
  CODE_SIGNING_ALLOWED=NO
Exit: 0

xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalBalanceTask2Fix1App \
  CODE_SIGNING_ALLOWED=NO
Exit: 0
```
