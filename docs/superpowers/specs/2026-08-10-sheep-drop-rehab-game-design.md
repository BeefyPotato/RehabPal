# Sheep Drop Rehabilitation Game Design

**Date:** 2026-08-10

**Status:** Approved design awaiting written-spec review

## Goal

Add a prescribed Sheep Drop rehabilitation game to RehabPal. The player uses the prescribed hand to bring all five fingertips together around a sheep, carries it over a fenced pen, and spreads the fingers to release it. Five settled placements complete the default session.

The scene and game loop follow `/Users/event/Downloads/test 9-3`, refined for RehabPal's shared hand-tracking lifecycle, deterministic scoring, accessibility, and testability.

## Scope

- Add Sheep Drop as a third `ExerciseKind` within the existing single mixed immersive space.
- Add a configurable `sheepDropRepetitions` prescription value; the demo prescription uses 5.
- Show `Completed X / Goal Y` throughout the session.
- Use the prescribed affected hand only.
- Use app-owned joint frames and RehabPal's existing live/demo, tracking-loss, recalibration, progress, and outcome contracts.
- Detect and track a suitable table through the same shared ARKit session used for hand tracking.
- Import Quaternius's low-poly sheep from Poly Pizza and convert it to a RealityKit-compatible USDZ asset.

Out of scope:

- Gesture-driven `DragGesture` pickup from the reference project.
- Two-finger pinch pickup.
- Independent ARKit sessions owned by individual views.
- Hand-force measurement or claims about measured grip strength.
- Persistence or rewards beyond the existing RehabPal outcome routing.

## Source Asset

- Model: **Sheep** by Quaternius
- Source: <https://poly.pizza/m/rgJXF570ZK>
- Source formats: GLTF/FBX
- License: CC0 1.0 / public domain
- Approximate geometry: 2,500 triangles

The downloaded original, converted USDZ, source URL, license text, conversion date, and conversion command must be recorded under `RehabPal/Resources/Sheep/`. Runtime code loads the USDZ from the application bundle. The visible hierarchy may be rescaled or reoriented, but its materials and proportions remain intact.

If automated download or conversion is unavailable, implementation stops and reports the blocked asset step. A procedural placeholder is not an accepted final substitute.

## Architecture

### Shared session integration

`ExerciseKind.sheepDrop` participates in the same `RehabSessionRequest`, `RehabSessionCoordinator`, `SharedRehabImmersiveView`, and `SessionOutcomePayload.gameplay` flow as Balance and Squeeze.

The coordinator continues to enforce:

- prescribed-hand matching;
- live tracking by default;
- explicit, labeled Demo Mode only after live startup failure;
- stale-frame and required-joint rejection;
- partial-attempt discard on tracking loss;
- processor reset and calibration acknowledgement after loss longer than two seconds;
- immutable app-owned tracking values at feature boundaries.

### Plane tracking

The existing live tracking engine is extended to run `HandTrackingProvider` and `PlaneDetectionProvider(alignments: [.horizontal])` through one `ARKitSession`. No game view starts or stops an ARKit session.

The engine converts plane anchors into an app-owned `DetectedTableSurface` value containing:

- identifier;
- timestamp;
- world transform;
- horizontal extent;
- tracking state.

The game accepts the first stable horizontal plane whose world-space height is strictly between 0.60 m and 0.95 m and whose extent can contain the required scene footprint. Stability requires consecutive compatible updates spanning at least 0.35 seconds with height drift no greater than 1.5 cm and normal drift no greater than 5 degrees.

Table detection is automatic. If no suitable surface is accepted within 3 seconds after the live game becomes active, the scene uses the reference fallback center `(0, 0.73, -0.55)` metres and labels placement as estimated. A table update may reposition the scene only before the first pickup begins. Once interaction starts, the scene transform is locked for the rest of the session.

Demo Mode uses the fallback placement and reports simulated provenance. It does not run ARKit.

### Pure game processor

`SheepDropSession` is a value-type state machine. It consumes:

- the current app-owned `HandJointFrame`;
- current sheep center and velocity in pen-local coordinates;
- the current timestamp;
- whether the sheep is outside the safe play volume.

It emits semantic events such as waiting, pickup began, carrying, released, successful placement, failed-drop reset, tracking paused, and completion. It owns pose stability, phase transitions, progress, and result creation. The RealityKit view owns entities, collision bodies, rendering, and application of emitted movement/physics events.

## Five-Fingertip Interaction

### Required joints

Pickup and carry require tracked positions for exactly these five tips on the prescribed hand:

- thumb tip;
- index finger tip;
- middle finger tip;
- ring finger tip;
- little finger tip.

The wrist and four metacarpal/knuckle reference joints are also required to calculate hand scale. Frames from the other hand or frames with any required joint below the coordinator's confidence threshold are unusable.

### Hand-size normalization

The processor computes hand scale as the median of valid distances from the wrist to the index, middle, ring, and little knuckles. Frames with a scale outside 4–14 cm are rejected as implausible.

For the five fingertip positions, the processor computes:

- the centroid;
- maximum pairwise fingertip separation divided by hand scale (`clusterRatio`);
- centroid distance from the sheep center divided by hand scale (`reachRatio`).

### Pickup

A pickup candidate requires all of the following:

- `clusterRatio <= 0.62`;
- `reachRatio <= 0.75`;
- all required joints are usable;
- the sheep is resting on the spawn/table surface;
- the pose remains valid continuously for 0.25 seconds.

When the dwell completes, the processor emits pickup. RealityKit changes the sheep body from dynamic to kinematic. The sheep follows an exponentially smoothed fingertip centroid, preserving the sheep-to-centroid offset captured at pickup so it does not snap into the hand.

The commanded sheep position is constrained to:

- no lower than one collision radius above the table;
- no more than 45 cm above the table;
- no farther than 65 cm horizontally from the scene center.

### Carry and release

While carrying, the pickup remains latched while `clusterRatio < 0.95`. Release requires `clusterRatio >= 0.95` continuously for 0.15 seconds. The distinct close and open thresholds provide hysteresis and prevent rapid grab/release oscillation.

On release, RealityKit changes the sheep body to dynamic and applies zero artificial velocity. Gravity and existing motion determine the drop. A low-pass filter on the carried position prevents frame jitter; its time constant is 0.08 seconds.

If fingertips become unusable during carry, the game freezes the sheep rather than releasing it. The common coordinator tracking-loss flow then decides whether the attempt resumes or resets.

## Scene and Physics

The reference scene dimensions are retained:

- table collision surface: 1.0 × 0.7 m;
- pen interior visual footprint: 0.36 × 0.36 m;
- table thickness: 0.015 m;
- fence height: 0.07 m;
- fence thickness: 0.012 m;
- spawn pad: 0.26 × 0.26 m;
- spawn-pad gap: 0.025 m;
- gravity: `(0, -6, 0)` m/s².

The pen contains a grass visual overlay, four static physical fence walls, and a wide physical table beneath both pen and spawn pad. The imported sheep is a visible child of a stable root entity. Physics uses a simple fitted collision shape independent of decorative mesh complexity, mass 0.15 kg, high damping, high friction, and low restitution.

The safe play volume extends 0.65 m horizontally from the scene center, from 0.15 m below the table to 0.60 m above it.

## Scoring and State Flow

Phases are:

1. `findingTable`
2. `waitingForHand`
3. `formingGrasp`
4. `carrying`
5. `falling`
6. `success`
7. `resetting`
8. `paused`
9. `complete`

A placement scores only after an explicit open-hand release. The sheep must then satisfy all conditions continuously for 0.25 seconds:

- its center is within the inner fence boundary on X and Z, excluding fence thickness;
- its center is no higher than 2.5 fitted collision radii above the floor;
- its linear speed is no greater than 0.08 m/s.

This settled interval refines the reference implementation so an airborne or fast-moving sheep cannot score.

After a successful placement:

- phase changes immediately to prevent duplicate scoring;
- progress increments once;
- a success message appears for 0.8 seconds;
- if the goal is not complete, the sheep respawns on the yellow pad with zero linear and angular velocity;
- if the goal is complete, the processor creates a `.sheepDrop` `GameplayResult` and the coordinator finishes the session.

After a failed release, the sheep remains physical until it either settles outside the pen, exits the safe play volume, or falls below the table. It then resets after a maximum 1.0-second observation window. Failed drops never decrement completed progress.

Default progress is `Completed 0 / Goal 5`. Prescription values greater than zero are supported.

## Tracking Loss and Recalibration

Brief loss:

- freezes the sheep in place;
- preserves completed placements;
- discards pickup/release dwell and settled-scoring dwell;
- does not interpret missing fingertips as an open-hand release.

Loss lasting at least two seconds:

- returns the sheep to the spawn pad;
- resets the Sheep Drop processor's partial state;
- requires the standard reset acknowledgement;
- requires one usable, open prescribed-hand frame to acknowledge processor calibration;
- leaves completed placements unchanged.

The game resumes only after the coordinator accepts both acknowledgements and the user confirms recalibration.

## HUD and Accessibility

The immersive HUD always shows:

- `Completed X / Goal Y`;
- `LIVE HAND TRACKING` or `DEMO FALLBACK — SIMULATED`;
- table state: detected or estimated;
- one phase-specific instruction.

Phase instructions include:

- “Finding a table…”
- “Bring all five fingertips together around the sheep.”
- “Hold the five-finger grasp steady.”
- “Carry the sheep over the fenced pen.”
- “Spread your fingers to release.”
- “Let the sheep settle.”
- “Sheep safely in the pen.”
- “Tracking paused — hold still.”
- “Recalibration required.”

Instructions must not claim that RehabPal measures force or verifies a physical grasp. The pickup is an inferred five-fingertip pose.

## Demo Mode

Demo Mode uses the same `SheepDropSession` processor, scoring thresholds, physics, HUD, goal, and completion path. It supplies deterministic simulated joint frames for:

1. open hand near spawn;
2. stable five-finger cluster near sheep;
3. carried centroid over pen;
4. stable open-hand release.

Controls may advance these stages, but must not directly increment progress or bypass settled-in-pen scoring. All resulting outcomes retain `.demo` provenance and a tracking note that the joint observations were simulated.

## Application Integration

- Add Sheep Drop to exercise selection and introductory instructions.
- Add a Sheep Drop instruction-media kind; if no dedicated video is supplied, use a static model preview and text rather than reusing an unrelated exercise video.
- Route the request through `SharedRehabImmersiveView`.
- Add the game goal to `Prescription` and `DemoData` fixtures.
- Accept `.sheepDrop` through the existing gameplay outcome validation and report flow.
- Existing Balance, Squeeze, wrist diagnostic, and finger diagnostic behavior must remain unchanged.

## Testing

Pure unit tests must cover:

- all five fingertips are required;
- wrong-hand and low-confidence frames are rejected;
- hand-scale validation and normalized cluster/reach ratios;
- pickup only after the 0.25-second close-pose dwell;
- no pickup when only thumb and index are close;
- carrying remains latched in the hysteresis band;
- release only after the 0.15-second open-pose dwell;
- missing fingertips during carry pause rather than release;
- smoothing and safe-volume clamping;
- scoring only after explicit release and 0.25-second settled dwell;
- airborne, fast, outside-pen, and pre-release states do not score;
- one score per sheep;
- failed-drop reset and velocity reset commands;
- prescribed goal and completion payload;
- tracking-loss partial reset with completed progress preservation;
- live versus demo tracking notes.

Plane-tracking tests must cover:

- table-height filtering;
- extent filtering;
- 0.35-second stability gate;
- drift rejection;
- automatic first-valid selection;
- three-second fallback;
- placement locking after interaction begins;
- independent removal/update behavior.

Integration tests must cover:

- `ExerciseKind` title and request routing;
- default goal 5;
- required-joint registration;
- shared immersive view selection;
- gameplay payload validation;
- progress and completion routing;
- no ARKit startup in Demo Mode;
- live tracking and plane tracking sharing one session lifecycle.

## Verification and Acceptance

Automated gates:

- asset exists in the bundle and `Entity(named:)` can compile against its resource name;
- targeted Sheep Drop and tracking tests compile and, where a destination exists, execute;
- full visionOS test bundle builds;
- app builds for generic visionOS;
- `git diff --check` passes;
- existing game tests remain green.

Physical Vision Pro acceptance:

- detected pen sits stably on a real table;
- the prescribed hand alone can pick up the sheep;
- thumb-index-only pinch does not pick it up;
- five-finger convergence reliably picks it up without visible snapping;
- spreading all fingers releases it;
- missing tracking never causes a release or score;
- fence/table collision and gentle gravity behave comfortably;
- only settled sheep inside the pen score;
- tracking interruption and long-loss recalibration work;
- five placements finish the session and route the result;
- HUD remains legible and does not occlude the hand or sheep.

Runtime tests and physical acceptance that cannot run in the development environment must be reported as unverified, never inferred from successful compilation.
