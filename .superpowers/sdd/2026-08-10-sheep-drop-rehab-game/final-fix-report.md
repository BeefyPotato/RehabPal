# Sheep Drop final whole-branch fix report

## Status

**DONE_WITH_CONCERNS.** All four Important findings in `final-review.md` are
resolved with regression-first changes, and the isolated radial safe-volume
Minor is also fixed. Focused and full generic visionOS builds pass. The bounded
selected simulator run did not finalize, and physical Vision Pro acceptance is
still unverified, so no fresh runtime-pass claim is made.

## Resolved findings

### 1. One observation is processed once

`SheepDropInputChronology` now accepts only a finite frame timestamp newer than
the last consumed timestamp. Live and Demo gesture phases consume that frame
once and pass its observation timestamp to `SheepDropSession`; render uptime is
used only for physics/deadline phases that do not infer hand dwell. Re-rendering
the coordinator's retained frame therefore cannot advance pickup or release.

Regressions cover duplicate and out-of-order rejection and prove that one
retained open frame leaves the processor carrying until a newer open sample
crosses the release dwell boundary.

### 2. Placement loss/change discards pickup dwell

Unlocked placement updates now report `acquired`, `unchanged`, or `invalidated`.
Removal or replacement of an existing placement enters the processor pause
path while a grasp is forming, which clears pickup/release/settling dwell and
partial progress. Scene-unavailable early returns apply the same forming-grasp
reset. Reacquisition requires a new hand observation and starts dwell from zero.

Regressions cover placement transition classification and a forming grasp
interrupted by removal and reacquisition after more than 0.25 seconds.

### 3. Selected tables reacquire after excessive pose jumps

When a suitable same-ID selected surface exceeds the 1.5 cm height or 5-degree
normal compatibility limits, `TableSurfaceSelector` now clears the stale
selection/placement and starts a fresh candidate at the new pose. It publishes
only after a new 0.35-second compatible stability interval. Locked placements
remain immutable.

The regression selects a surface, applies a same-anchor height/normal jump,
observes immediate placement loss, and proves selection resumes only at the new
stability deadline.

### 4. ARKit provider transitions retain provider identity

Production ARKit events are mapped to app-owned provider roles (`hand`, `world`,
`plane`) and lifecycle states before policy is applied. Plane-only pause/stop
clears and restarts table acquisition/fallback without emitting a global hand
interruption or failure. Hand/world pauses still interrupt shared tracking, and
hand/world stops still emit the existing fatal provider failure. The injected
provider-state stream is generation-guarded and uses the same production policy
path, preserving the single-session lifecycle.

Regressions cover plane-only table invalidation with a running hand engine and
the retained hand-pause/world-stop semantics.

### 5. Radial safe play volume

Horizontal containment now compares the XZ vector length with the 0.65 m
radius. The diagonal regression rejects `(0.60, 0.60)` while accepting a point
inside the radius and retaining vertical bounds.

## TDD and verification evidence

### RED

The focused generic test-bundle build for `ExerciseSessionTests`,
`TableSurfaceTests`, and `HandTrackingEngineTests` used derived data
`/private/tmp/RehabPalSheepFinalFixRed` and exited **65**. The expected errors
were the missing provider-state seam and new interaction/placement/safe-volume
contracts. No production fix had been applied.

### GREEN compile evidence

- Focused three-class generic `build-for-testing` after the minimal fixes,
  derived data `/private/tmp/RehabPalSheepFinalFixGreen`: **exit 0**.
- Strengthened focused three-class generic `build-for-testing` including the
  end-to-end chronology and placement-gap regressions, derived data
  `/private/tmp/RehabPalSheepFinalFixGreen2`: **exit 0**.
- Full generic visionOS `build-for-testing`, derived data
  `/private/tmp/RehabPalSheepFinalFixFull`: **exit 0**.
- Generic visionOS application build, derived data
  `/private/tmp/RehabPalSheepFinalFixApp`: **exit 0**.

The quiet builds emitted no Swift compiler warning or error. They emitted the
same environment-level Xcode destination diagnostic recorded in the initial
report.

### Bounded runtime evidence

The first selected simulator attempt used an external alarm wrapper and exited
**74** before build/test because CoreSimulator and its cache/log paths were
unavailable in that wrapped sandbox. It is not a product result.

One direct serial run then selected only the eight new regressions, disabled
parallel testing, and targeted the concrete Apple Vision Pro visionOS 27.0
simulator. It reached `Testing started` but emitted no result within the
240-second bound. It was interrupted (`BUILD INTERRUPTED`, exit 1). Runtime
execution is therefore **UNVERIFIED**; no pass/fail count is claimed and no
further simulator retry was made.

### Static gates

- `git diff --check`: **exit 0** before report staging.
- No `DragGesture` or `targetedToAnyEntity` appears in Sheep Drop.
- `Sheep.usdz` SHA-256 remains
  `08396da7f8d95febacf3f12aa757465a23262cc8eb284b5650df19068d10edf4`.
- The final-report full-runtime wording is narrowed: the preserved exact
  before/after comparison begins at `000dc33` and proves only that Task 5 added
  no new failure, not that the entire feature is runtime-equivalent to
  `93af7d7`.

## Files changed

- `RehabPal/Features/SheepDrop/SheepDropView.swift`
- `RehabPal/Tracking/HandTrackingEngine.swift`
- `RehabPal/Tracking/TableSurface.swift`
- `RehabPalTests/ExerciseSessionTests.swift`
- `RehabPalTests/HandTrackingEngineTests.swift`
- `RehabPalTests/TableSurfaceTests.swift`
- initial `final-report.md` evidence correction
- this `final-fix-report.md`

## Remaining concerns

1. The new regressions compile but the selected simulator runner did not
   finalize within the bound; fresh runtime XCTest remains unverified.
2. A completed full-suite comparison against feature baseline `93af7d7` is not
   available. The historical exact eight-failure comparison begins at
   `000dc33`.
3. Direct production ARKit provider construction and `PlaneAnchor` conversion
   still lack injected runtime execution coverage; provider-state policy now
   has an app-owned injected seam.
4. Every item in the physical Vision Pro checklist remains
   `UNVERIFIED — physical Vision Pro required`.
