# Task 5 — Automated wrist and finger diagnostics report

## Status

DONE_WITH_CONCERNS

## Delivered

- Replaced fixture/button wrist completion with a pure affected-hand `WristDiagnosticProcessor` hosted by the shared mixed immersive space. It calibrates neutral from the prescribed hand and four level knuckles, then automatically advances through center, forward, backward, left, and right for the prescribed attempts.
- Enforced a 20-degree directional target with inclusive ±5-degree primary and 5-degree off-axis tolerances, continuous 100 ms-or-better samples for a 0.5-second hold, and a return inside 5 degrees of neutral before an attempt counts.
- Added unclamped yaw-free diagnostic wrist measurement while retaining the existing independently clamped 20-degree gameplay path.
- Computes the clamped wrist result as `100 - 2 * mean target error degrees - 3 * mean hold jitter degrees`. Target error is the two-axis distance from the prescribed target; hold jitter is the within-attempt primary-axis standard deviation.
- Tracks confidence from unique valid versus required frame timestamps. Missing, wrong-hand, incomplete, non-finite, stale, and tracking-loss inputs cannot advance a diagnostic; interruption discards partial state while preserving completed attempts.
- Buffers every timestamped diagnostic tracking poll in coordinator publication order and drains each poll exactly once, so render cadence can neither duplicate nor overwrite missing observations.
- Added `FingerROMDiagnosticProcessor` for sequential thumb, index, middle, ring, and little-finger attempts. It converts joint interior angles to flexion with `180 - interior angle`, requires 0.3 seconds of continuously stable extension, captures per-joint minima/maxima, requires at least 15 degrees total excursion, and requires return within 8 degrees.
- Thumb attempts additionally require at least 25% thumb-to-little-finger opposition-distance reduction and return within 10% of the extension baseline.
- Returns actual `AssessmentResult.WristResult` and five `DigitROMSummary` values with captured extrema, excursion, consistency, attempt counts, and confidence. The default finger protocol advances automatically through 10 attempts.
- Added one reusable diagnostic HUD with `Attempt X / Goal Y`, subject, phase, partial progress, confidence, pause disclosure, and explicit `SIMULATED` provenance.
- Demo Mode drives the same wrist and finger processors with deterministic samples; the shared coordinator retains `.demo` provenance on the typed outcomes.
- Removed the old assessment completion/capture buttons from the window views. Both diagnostics now finish only through processor progress and coordinator-routed immersive outcomes.

## TDD evidence

### RED — core diagnostic contracts

```sh
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/DiagnosticProcessorTests \
  -derivedDataPath /private/tmp/RehabPalTask5Red
```

- Exit 65 / `** TEST BUILD FAILED **` as expected because `WristAssessmentTarget`, `WristDiagnosticProcessor`, `FingerROMMetrics`, `FingerDiagnosticSample`, and `FingerROMDiagnosticProcessor` did not exist.
- The tests were authored first for the required order, tolerance boundaries, continuous hold, neutral return, scoring, frame confidence, flexion conversion, stable extension, excursion/return thresholds, thumb opposition, extrema, ten-attempt progress, chirality, and interruption behavior.

### RED — shared HUD and continuity/scoring hardening

- `/private/tmp/RehabPalTask5HUDRed`: exit 65 because `DiagnosticHUDPresentation` did not exist.
- `/private/tmp/RehabPalTask5ContinuityRed`: exit 65 because the required continuous-sampling configuration did not exist.
- `/private/tmp/RehabPalTask5ScoreRed`: exit 65 because two-axis `targetErrorDegrees` did not exist.
- `/private/tmp/RehabPalTask5ObservationRed`: exit 65 because timestamped `HandJointFrameObservation` consumption did not exist.
- `/private/tmp/RehabPalTask5ObservationQueueRed`: exit 65 because the coordinator did not yet provide ordered buffered diagnostic observation consumption.
- `testCoordinatorRejectsDiagnosticGoalThatCannotBeDistributedAcrossFiveTargets` was authored before the coordinator goal guard; under the previous `goal > 0` contract, a goal of 6 entered the live session and would fail the new `.invalidGoal` assertion.

### GREEN — focused diagnostics

```sh
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/DiagnosticProcessorTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -derivedDataPath /private/tmp/RehabPalTask5ResumeFocused \
  CODE_SIGNING_ALLOWED=NO
```

- Exit 0 / `** TEST BUILD SUCCEEDED **`; the focused diagnostic suite compiled and linked after review-driven duplicate-timestamp, flexion-direction, and per-attempt confidence tests were added.

### GREEN — complete test target and app

```sh
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalTask5ResumeFull \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalTask5ResumeApp \
  CODE_SIGNING_ALLOWED=NO
```

- Both commands exited 0. The complete app and XCTest bundle compiled and linked, and the standalone visionOS app build succeeded.
- `git diff --check` exited 0.

### XCTest execution limitation

```sh
xcodebuild test -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'platform=visionOS,id=00008112-000818D801C1A01E' \
  -only-testing:RehabPalTests/DiagnosticProcessorTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -derivedDataPath /private/tmp/RehabPalTask5FinalDeviceTests
```

- Xcode built and signed the focused target but could not launch it because the connected Apple Vision Pro was locked (`Unlock Apple Vision Pro to Continue`). The destination wait was interrupted.
- No visionOS Simulator device is installed, so runtime XCTest evidence remains pending on an unlocked headset or installed simulator.

## Review and scope

- Re-read the exact Task 5 brief and approved design after implementation and checked every threshold, sequence, progress, result, tracking-loss, and provenance requirement against the processor contracts and immersive routing.
- Independent review identified duplicate/overwritten tracking observations, unsigned finger excursion, session-wide finger attempt confidence, and malformed diagnostic goals. All were corrected and protected by focused regressions; final re-review found no remaining Critical, Important, or Minor issue and marked Task 5 ready to merge.
- Diagnostic goals that cannot be distributed across the five wrist targets or five digits are rejected as `.invalidGoal` before live tracking starts.
- The balance and squeeze implementations were not changed. The adjacent `MovementMath` refactor preserves their original clamped wrist API; the existing exercise regression target compiles and links.
- The unrelated untracked `docs/superpowers/plans/2026-08-09-pet-hunger.md` remains untouched and will not be staged.

## Concerns

- Runtime XCTest could not execute because the connected headset is locked and no visionOS Simulator is installed.
- Physical Vision Pro acceptance remains required for wrist axis direction, neutral comfort, ARKit sampling continuity, finger-chain angle behavior, thumb opposition distance, HUD placement, and natural automatic progression.
- The brief specifies the 0.3-second extension duration but not a stability band or sampling-gap limit. This implementation uses a 3-degree per-joint stability band and a maximum 100 ms inter-frame gap for both continuous holds; both should be clinically validated.
- Existing unrelated compiler warnings remain in `InstructionMediaCard.swift` deprecation usage and report-model actor isolation. Task 5 adds no new warning in the final build output.

## Commit

The Task 5 commit is the commit containing this report; its hash is recorded in the task handoff.
