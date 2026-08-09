# Task 5 Report — RealityKit Sheep Drop Scene and Shared Routing

## Status

**DONE_WITH_CONCERNS.** The complete Task 5 implementation compiles for
generic visionOS, and the focused serial Apple Vision Pro simulator suite
passes 94/94. Physical Vision Pro placement, hand interaction, and comfort
acceptance remain unverified. The full serial runtime suite still reports the
same eight unrelated failures recorded before Task 5 at commit `000dc33`.

## RED → GREEN

### RED

Tests were added first for:

- exhaustive shared immersive routing, including `.exercise(.sheepDrop)`;
- exact Sheep Drop required-joint registration before the first poll;
- Demo Mode avoiding live ARKit and publishing a valid open five-tip frame;
- generation-safe reset acknowledgement and open-hand-only calibration;
- matching `.sheepDrop` gameplay completion;
- reference dimensions, pen-local floor/transform math, and placement locking;
- exact HUD provenance/table/phase copy; and
- deterministic demo frames crossing the real `SheepDropSession` processor
  without directly scoring.

The targeted generic `build-for-testing` exited 65. Its failures were the
intended missing `SharedRehabImmersiveRoute`, `SheepDropSceneConfiguration`,
`SheepDropCoordinateSpace`, `SheepDropPlacementState`,
`SheepDropHUDPresentation`, and `SyntheticMovementSource.setSheepDropPose`
APIs.

### GREEN

Implemented:

- one RealityKit root with gravity `(0, -6, 0)`, a 1.0 × 0.7 m physical table,
  0.36 m grass pen, four 0.07 m static fence walls, and 0.26 m yellow spawn pad;
- a 0.15 kg fitted spherical sheep collision root using friction 0.7/0.55,
  restitution 0.1, and damping 1.2;
- cancellation-aware asynchronous `Sheep.usdz` loading, with the normalized
  visible model attached as `SheepVisible` beneath the collision root;
- pen-local position, velocity, and joint-frame conversion with floor `y = 0`;
- detected/estimated placement application and a first-pickup placement latch;
- idempotent absolute physics commands for pickup, carry, release, freeze, and
  reset, plus one-shot completion delivery;
- exact required-joint publication before polling and on every scene update;
- coordinator calibration acceptance only for a current, usable, open
  five-fingertip frame in the active reset generation;
- processor-driven progress/completion and deterministic synthetic
  open/cluster/carry/open demo frames; and
- exhaustive shared routing with `finishSheepDrop(_:)` forwarding
  `.gameplay(result)`.

## Verification evidence

- Focused serial simulator suite: **94 passed, 0 failed, 0 skipped** on Apple
  Vision Pro, visionOS Simulator 27.0. This includes Sheep Drop processor,
  table selector, hand-tracking engine, coordinator, asset, routing, transform,
  placement-lock, HUD, and demo-path coverage.
- Full generic visionOS `build-for-testing`: **exit 0**.
- Generic visionOS app build: **exit 0**.
- `git diff --check`: **exit 0**.
- Static Sheep Drop scan: no `DragGesture` or `targetedToAnyEntity` usage.
- `Sheep.usdz` SHA-256 remains
  `08396da7f8d95febacf3f12aa757465a23262cc8eb284b5650df19068d10edf4`.

The post-change full serial runtime suite exited 65 with the exact same eight
pre-existing failures observed at `000dc33`:

1. `DiagnosticProcessorTests.testThumbRequiresTwentyFivePercentOppositionReductionAndTenPercentReturn()`
2. `ExerciseSessionTests.testBalancePauseFreezesPhysicsDiscardsThePartialBallAndCanRequireRecalibration()`
3. `ExerciseSessionTests.testSqueezeCountsCloseHoldReopenPhasesAndStopsAtExactGoal()` (reported three times)
4. `ExerciseSessionTests.testSqueezeDemoGraspSamplingCrossesOneSecondInOneAction()`
5. `ExerciseSessionTests.testSqueezeInterruptionHidesFaceDiscardsPartialRepAndPreservesCompletedReps()`
6. `MovementDetectorTests.testSqueezeGraspGateRequiresOneStableSecondOfCuppedHandMetrics()`

The redundant full-suite comparison also spent 600 seconds collecting
simulator diagnostics before reporting that unchanged failure set. Per task
scope, no unrelated Balance, Squeeze, or diagnostic code was altered.

## Self-review

- All processor observations and commands are pen-local; only the scene
  boundary converts world joint transforms and physics velocities.
- The table transform remains live only until `.pickupBegan`, then the local
  placement latch prevents later plane updates from moving the scene.
- Missing fingertips freeze rather than release. Long loss resets the sheep
  once per coordinator generation, preserves completed placements, and waits
  for reset plus open-frame calibration acknowledgements.
- Physical commands assign mode, position, and velocity instead of toggling or
  applying impulses, so duplicate render updates are harmless.
- Only `.placementSucceeded` inside `SheepDropSession` can increase completed
  progress; demo controls only publish synthetic frames and apply processor
  events.
- The HUD always retains `Completed X / Goal Y`, provenance, table state, and
  an approved phase instruction, including while the asset is loading.

## Concerns and unverified acceptance

- No physical Vision Pro was available. Real-table stability, visual model
  scale/orientation, fence collision feel, pickup comfort, HUD occlusion, and
  interruption behavior require the approved device acceptance pass.
- The known non-Task-5 full-runtime failures remain outside this task's scope.
