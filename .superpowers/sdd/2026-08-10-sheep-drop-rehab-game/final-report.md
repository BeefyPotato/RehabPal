# Sheep Drop final integration report

## Status

**DONE_WITH_CONCERNS.** The complete branch builds for generic visionOS, the
focused generic test bundle builds, the static/specification review found no
concrete integration defect, and the approved sheep asset remains intact.
Fresh runtime XCTest did not complete within the bounded simulator window, so
it is not reported as passing. Physical Vision Pro acceptance also remains
unverified.

No production source was changed during Task 6. This report is the only Task 6
change.

## Reviewed range and commits

The full implementation diff was reviewed from baseline `93af7d7` through
Task 5 head `39c70ec`:

1. `b2e2474` — Add Sheep Drop exercise prescription
2. `0ae67b7` — Fix Sheep Drop launch and report disclosure
3. `6bb0255` — Add shared table surface tracking
4. `b79ccf7` — Add five-fingertip Sheep Drop processor
5. `d19b736` — Preserve Sheep Drop lifecycle state
6. `60ab986` — Reject stale Sheep Drop positions
7. `000dc33` — Import CC0 sheep model
8. `7e1f5fd` — Add immersive Sheep Drop game
9. `39c70ec` — Fix Sheep Drop review findings

The audit covered the approved design, existing-game integration, lifecycle
ownership, event/command idempotence, stale-frame behavior, demo provenance,
and asset license/provenance. No concrete Task 6 defect was found.

## Fresh Task 6 verification

All commands ran from the linked worktree on 2026-08-10.

### Compile verification

- Focused six-class generic `xcodebuild build-for-testing` using derived data
  `/private/tmp/RehabPalSheepFocused`: **exit 0**.
- Full generic `xcodebuild build-for-testing` using derived data
  `/private/tmp/RehabPalSheepFull`: **exit 0**.
- Generic application `xcodebuild build` using derived data
  `/private/tmp/RehabPalSheepApp`: **exit 0**.

The three quiet builds emitted no Swift compiler warning or error. Xcode did
emit its environment-level diagnostic `IDERunDestination: Supported platforms
for the buildables in the current scheme is empty.` The previously recorded
AVPlayer deprecation warning was not emitted by these fresh quiet builds.

### Runtime destination and bounded attempt

`xcodebuild -showdestinations -project RehabPal.xcodeproj -scheme RehabPal`
exited 0 and listed a concrete Apple Vision Pro simulator:

- identifier `2005850E-20C9-4441-B27B-1F665EFB1164`
- visionOS Simulator 27.0, arm64

The initial `test-without-building` attempt against that simulator exited 65
before XCTest because the preceding artifact had been built for generic
`xros`, not `xrsimulator` (`RehabPal.app` was absent from the simulator product
directory). This is an invocation/artifact mismatch, not a test failure.

The corrected focused concrete-destination `xcodebuild test` used:

- only the six classes in the Task 6 brief;
- `-parallel-testing-enabled NO`;
- `-maximum-concurrent-test-simulator-destinations 1`; and
- derived data `/private/tmp/RehabPalSheepFocusedRuntime`.

It entered `Testing started` but produced no test result before simulator
diagnostic collection timed out. Xcode reported 635.362 seconds elapsed,
`TEST INTERRUPTED`, and **exit 75**. Therefore fresh Task 6 runtime XCTest is
**UNVERIFIED**; no pass/fail count is claimed and no additional simulator run
was started.

### Prior runtime evidence and exact baseline comparison

The SDD ledger and committed per-task reports preserve the completed runtime
evidence:

- Task 1: 16 passed, 0 failed.
- Task 2: 44 passed, 0 failed.
- Task 3: 48 passed, 0 failed.
- Task 4: 6 asset tests passed.
- Task 5 focused suite: 94 passed, 0 failed; the three post-review regressions
  also passed.

Task 5's committed full serial comparison against asset baseline `000dc33`
reported the same exact eight unrelated failures before and after Task 5:

1. `DiagnosticProcessorTests.testThumbRequiresTwentyFivePercentOppositionReductionAndTenPercentReturn()`
2. `ExerciseSessionTests.testBalancePauseFreezesPhysicsDiscardsThePartialBallAndCanRequireRecalibration()`
3. `ExerciseSessionTests.testSqueezeCountsCloseHoldReopenPhasesAndStopsAtExactGoal()` (reported three times)
4. `ExerciseSessionTests.testSqueezeDemoGraspSamplingCrossesOneSecondInOneAction()`
5. `ExerciseSessionTests.testSqueezeInterruptionHidesFaceDiscardsPartialRepAndPreservesCompletedReps()`
6. `MovementDetectorTests.testSqueezeGraspGateRequiresOneStableSecondOfCuppedHandMetrics()`

That is eight reported failures because item 3 appears three times. No new
failure appeared in that exact baseline comparison. Task 6 did not repeat the
full runtime suite after the bounded focused simulator run failed to finalize;
the prior exact comparison is retained as the available full-runtime evidence.

### Static gates

- `git diff --check`: **exit 0**.
- `git diff --check 93af7d7..HEAD`: **exit 0**.
- `git status --short --branch`: clean `feature/sheep-drop-game` before this
  report was created.
- `rg -n "DragGesture|targetedToAnyEntity" RehabPal/Features/SheepDrop`:
  no matches.
- Required five-fingertip, `SIMULATED`, live/demo, table, and phase disclosure
  strings are present in Sheep Drop and exercise-introduction views.
- The exact `Completed X / Goal Y` rendering is supplied by the shared
  `SessionProgressLabel`/`SessionProgressHUD` used by `SheepDropHUD`; its
  literal is in `RehabPal/Session/SessionProgressHUD.swift`, outside the
  brief's narrow SheepDrop/Views text-search paths.

## Asset provenance and integrity

- Model: **Sheep** by Quaternius.
- Canonical source: <https://poly.pizza/m/rgJXF570ZK>.
- Published GLB URL:
  <https://static.poly.pizza/d42145b6-ae20-48cd-ba36-63b03f901c32.glb>.
- License: CC0 1.0 Universal / public domain.
- `Sheep.glb` SHA-256:
  `0b259e1a5dbf4463901667e11529f229193a6f3869cecf30508f8cb5bbe3131f`.
- `Sheep.usdz` SHA-256:
  `08396da7f8d95febacf3f12aa757465a23262cc8eb284b5650df19068d10edf4`.

The fresh USDZ checksum exactly matches the committed attribution record and
Task 4 ledger. The attribution records the exact Blender 5.2.0 LTS conversion
command and successful `usdchecker --arkit`, `usdzip`, and `usdcat`
validation. Runtime selection/fitting retains only the sheep hierarchy and
does not replace it with a procedural model.

## Integration review conclusions

- Prescription/routing: Sheep Drop is the third prescribed exercise, defaults
  to goal 5, requires an explicit Begin action, and routes a matching gameplay
  result through the shared immersive coordinator.
- Shared tracking: the app-owned engine is the only ARKit session owner and
  runs hand/world/plane providers together. Demo Mode does not start ARKit.
- Table placement: strict height/extent/stability rules, three-second fallback,
  removal handling, and the first-pickup placement lock match the design.
- Interaction/scoring: all five tips and hand-scale references are required;
  close/open dwell, hysteresis, filtering, safe-volume clamps, explicit-release
  settled scoring, reset deadlines, and exact-goal completion are processor
  owned.
- Lifecycle/stale data: brief loss freezes instead of releasing, long loss
  preserves completed placements while resetting partial state, coordinator
  generations reject obsolete updates, and non-monotonic processor timestamps
  cannot advance dwell or scoring.
- Idempotence: progress can increment only on the processor's settled placement
  transition; physics commands are absolute; scene placement locks once; and
  completion delivery is guarded once at the view boundary.
- Existing games: no Balance, Squeeze, wrist-diagnostic, or finger-diagnostic
  behavior was intentionally redesigned. The full generic products compile,
  and the only known full-runtime failures are the unchanged baseline set
  listed above.
- Disclosure/accessibility: the HUD keeps goal progress, provenance, table
  state, and phase guidance visible, and copy explicitly says the pose is
  inferred rather than force-measured.

Resolved findings from prior review rounds include launch/report disclosure,
lifecycle timestamp/pause preservation, stale Sheep Drop positions, unlocked
placement invalidation, sheep-only asset subtree selection, and removal of
Demo-only controls from live sessions. Task 6 found no additional concrete
finding requiring a TDD fix.

The Task 2 minor remains: injected tests do not directly execute production
ARKit provider construction or `PlaneAnchor` mapping. Those boundaries compile
and are structurally reviewed, but require device/runtime acceptance.

## Physical Vision Pro acceptance checklist

- **UNVERIFIED — physical Vision Pro required:** detected pen sits stably on a
  real table.
- **UNVERIFIED — physical Vision Pro required:** only the prescribed hand can
  pick up the sheep.
- **UNVERIFIED — physical Vision Pro required:** thumb-index-only pinch cannot
  pick up the sheep.
- **UNVERIFIED — physical Vision Pro required:** five-finger convergence picks
  up reliably without visible snapping.
- **UNVERIFIED — physical Vision Pro required:** spreading all fingers releases
  the sheep.
- **UNVERIFIED — physical Vision Pro required:** missing tracking never causes
  a release or score.
- **UNVERIFIED — physical Vision Pro required:** fence/table collisions and
  gentle gravity feel comfortable.
- **UNVERIFIED — physical Vision Pro required:** only settled sheep inside the
  pen score.
- **UNVERIFIED — physical Vision Pro required:** interruption and long-loss
  recalibration work end to end.
- **UNVERIFIED — physical Vision Pro required:** five placements finish the
  session and route the result.
- **UNVERIFIED — physical Vision Pro required:** HUD remains legible without
  occluding the hand or sheep.

## Remaining concerns

1. Fresh Task 6 simulator XCTest did not finalize within the bounded window;
   runtime status relies on the committed earlier per-task runs and Task 5's
   exact baseline comparison.
2. The complete physical Vision Pro checklist is unverified.
3. The exact eight unrelated full-suite baseline failures remain outside the
   Sheep Drop task scope.
4. Production ARKit plane-provider construction and `PlaneAnchor` conversion
   still lack direct injected runtime execution coverage.
