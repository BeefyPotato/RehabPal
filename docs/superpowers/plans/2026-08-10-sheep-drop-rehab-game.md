# Sheep Drop Rehabilitation Game Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a prescribed five-fingertip Sheep Drop game that detects a table, lets the affected hand carry an imported sheep into a physical pen, and completes after the prescribed number of settled placements.

**Architecture:** Extend RehabPal's shared ARKit boundary with app-owned table observations, then implement grasp/scoring as a pure `SheepDropSession` state machine. A focused RealityKit view applies its events to the imported sheep and reference pen scene while the existing coordinator owns tracking loss, provenance, progress, and completion.

**Tech Stack:** Swift 5, SwiftUI, RealityKit, ARKit hand/plane tracking, Observation, XCTest, Xcode visionOS build tools, Reality Converter or `usd_from_gltf`/`xcrun usdz_converter` where available.

## Global Constraints

- Work on `feature/game-enhancements`; do not merge or push without a separate user choice.
- Preserve `docs/superpowers/plans/2026-08-09-pet-hunger.md` unchanged and untracked.
- Follow `docs/superpowers/specs/2026-08-10-sheep-drop-rehab-game-design.md` exactly.
- Use only the prescribed affected hand and immutable app-owned joint/plane values at feature boundaries.
- Pickup requires all five fingertips; two-finger pinch must not pick up the sheep.
- Default Sheep Drop goal is 5 and the HUD always shows `Completed X / Goal Y`.
- Live tracking remains default; Demo Mode is explicit, labeled, and uses the same processor.
- Use one shared `ARKitSession` for hand, world, and plane providers; game views never start ARKit.
- The final model must be Quaternius's CC0 sheep from <https://poly.pizza/m/rgJXF570ZK>; no procedural final substitute.
- Existing Balance, Squeeze, wrist diagnostic, and finger diagnostic behavior must remain unchanged.
- Runtime/device checks unavailable in this environment must be reported as unverified.

---

## File Structure

- `RehabPal/Tracking/TableSurface.swift`: app-owned table values, pure stability selector, fallback timing, and placement lock.
- `RehabPal/Tracking/HandTrackingEngine.swift`: one-session hand/world/plane provider wiring and published selected table.
- `RehabPal/Session/RehabSessionCoordinator.swift`: expose app-owned table placement to the active game and clear it with session lifecycle.
- `RehabPal/Features/SheepDrop/SheepDropSession.swift`: pure five-finger grasp, release, scoring, reset, and result state machine.
- `RehabPal/Features/SheepDrop/SheepDropView.swift`: RealityKit pen/table/sheep scene, physics application, HUD, and demo controls.
- `RehabPal/Resources/Sheep/Sheep.usdz`: converted runtime sheep asset.
- `RehabPal/Resources/Sheep/LICENSE-AND-ATTRIBUTION.txt`: CC0 provenance and conversion record.
- `RehabPal/Models/Prescription.swift`: Sheep Drop exercise kind and prescribed repetitions.
- `RehabPal/Models/DemoData.swift`: Sheep Drop fixture goal/provenance notes.
- `RehabPal/Session/SharedRehabImmersiveView.swift`: immersive routing and outcome completion.
- `RehabPal/Views/DailyRoutineView.swift`: third exercise card and dose.
- `RehabPal/Views/ExerciseDemoView.swift`: Sheep Drop introduction and active-session instructions.
- `RehabPal/Views/InstructionMediaCard.swift`: Sheep Drop static preview kind.
- `RehabPalTests/TableSurfaceTests.swift`: pure table-selection tests.
- `RehabPalTests/HandTrackingEngineTests.swift`: provider lifecycle/publication regression coverage.
- `RehabPalTests/SheepDropSessionTests.swift`: grasp, release, physics-observation, scoring, loss, and result tests.
- `RehabPalTests/ExerciseSessionTests.swift`: prescription, routing, payload, and fixture integration tests.
- `RehabPalTests/AssetCatalogTests.swift`: bundled sheep asset/provenance validation.

---

### Task 1: Exercise Contract and Prescription Integration

**Files:**
- Modify: `RehabPal/Models/Prescription.swift`
- Modify: `RehabPal/Models/DemoData.swift`
- Modify: `RehabPal/Views/DailyRoutineView.swift`
- Modify: `RehabPal/Views/ExerciseDemoView.swift`
- Modify: `RehabPal/Views/InstructionMediaCard.swift`
- Test: `RehabPalTests/ExerciseSessionTests.swift`
- Test: `RehabPalTests/AppStateTests.swift`

**Interfaces:**
- Produces: `ExerciseKind.sheepDrop`, `Prescription.sheepDropRepetitions: Int`, and `goal(for: .exercise(.sheepDrop))`.
- Preserves: existing `GameplayResult` and `SessionOutcomePayload.gameplay` contracts.

- [ ] **Step 1: Write failing exercise-contract tests**

Add tests that assert:

```swift
XCTAssertEqual(ExerciseKind.sheepDrop.title, "Sheep Drop")
XCTAssertEqual(Prescription.demo.sheepDropRepetitions, 5)
XCTAssertEqual(
    Prescription.demo.sessionRequest(for: .exercise(.sheepDrop)).goal,
    5
)
XCTAssertEqual(
    GameplayResult.fixture(for: .sheepDrop).exercise,
    .sheepDrop
)
```

Update AppState coverage to prove daily assessment unlocks only after every value in the now-three-case `ExerciseKind.allCases` has completed.

- [ ] **Step 2: Verify RED**

Run:

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/ExerciseSessionTests \
  -only-testing:RehabPalTests/AppStateTests \
  -derivedDataPath /private/tmp/RehabPalSheepTask1Red CODE_SIGNING_ALLOWED=NO
```

Expected: exit 65 because `.sheepDrop` and `sheepDropRepetitions` do not exist.

- [ ] **Step 3: Implement the minimal contracts and UI copy**

Add `case sheepDrop` and exhaustive titles/icons. Add `sheepDropRepetitions` to `Prescription`, set `.demo` to 5, and map it in `goal(for:)`.

Render a third routine card with dose `"5 settled sheep placements"`. In `ExerciseDemoView`, require the Begin button like Squeeze and use copy that explicitly says all five fingertips are inferred, not force-measured. Add `.sheepDrop` to `InstructionMediaKind`; render a sheep/system-animal static preview when no MP4 exists.

Update `GameplayResult.fixture(for:)` with an exhaustive switch rather than a balance-versus-other ternary.

- [ ] **Step 4: Verify GREEN and regressions**

Run the Task 1 build-for-testing command again with derived data `RehabPalSheepTask1Green`; expected exit 0.

- [ ] **Step 5: Commit Task 1**

```bash
git add RehabPal/Models/Prescription.swift RehabPal/Models/DemoData.swift \
  RehabPal/Views/DailyRoutineView.swift RehabPal/Views/ExerciseDemoView.swift \
  RehabPal/Views/InstructionMediaCard.swift RehabPalTests/ExerciseSessionTests.swift \
  RehabPalTests/AppStateTests.swift
git commit -m "Add Sheep Drop exercise prescription"
```

---

### Task 2: App-Owned Table Detection

**Files:**
- Create: `RehabPal/Tracking/TableSurface.swift`
- Modify: `RehabPal/Tracking/HandTrackingEngine.swift`
- Modify: `RehabPal/Session/RehabSessionCoordinator.swift`
- Modify: `RehabPal/Session/RehabSessionContracts.swift`
- Create: `RehabPalTests/TableSurfaceTests.swift`
- Modify: `RehabPalTests/HandTrackingEngineTests.swift`
- Modify: `RehabPalTests/RehabSessionCoordinatorTests.swift`

**Interfaces:**
- Produces: `DetectedTableSurface`, `TablePlacement`, `TableSurfaceSelector`, `LiveHandJointSession.tablePlacement`, and `RehabSessionCoordinator.currentTablePlacement`.
- Consumes: the existing generation-safe `HandTrackingEngine` lifecycle.

- [ ] **Step 1: Write failing pure table-selector tests**

Define tests against this intended API:

```swift
var selector = TableSurfaceSelector(scanStartedAt: 10)
let candidate = DetectedTableSurface(
    id: UUID(), timestamp: 10,
    transform: matrixWithTranslation([0, 0.73, -0.55]),
    extent: [1.0, 0.7], isTracked: true
)
XCTAssertNil(selector.receive(.added(candidate), at: 10))
XCTAssertEqual(
    selector.receive(.updated(candidate.with(timestamp: 10.36)), at: 10.36)?.source,
    .detected
)
```

Cover height rejection at 0.60/0.95 boundaries, insufficient extent, >1.5 cm height drift, >5° normal drift, removed anchors, first-valid automatic selection, fallback at 3 seconds, and `lock()` preventing later movement.

- [ ] **Step 2: Verify selector RED**

Run a targeted generic visionOS test-bundle build for `TableSurfaceTests`; expected exit 65 for missing types.

- [ ] **Step 3: Implement app-owned values and selector**

Create:

```swift
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
    enum Source: Equatable, Sendable { case detected, estimated }
    let transform: simd_float4x4
    let source: Source
}
```

Implement the exact 0.60–0.95 m, footprint, 0.35 s, 1.5 cm, 5°, and 3 s rules. Keep selector math independent of ARKit.

- [ ] **Step 4: Write failing engine/coordinator lifecycle tests**

Extend the injectable engine seam to assert one start boundary owns hand/world/plane work, stop clears table publication, old-generation plane updates are ignored, Demo Mode exposes estimated placement without starting ARKit, and a coordinator cancel clears/invalidates placement.

- [ ] **Step 5: Verify integration RED**

Run targeted builds for `HandTrackingEngineTests` and `RehabSessionCoordinatorTests`; expected exit 65 because the live-session table API is absent.

- [ ] **Step 6: Wire PlaneDetectionProvider through the shared engine**

In the production initializer, construct `PlaneDetectionProvider(alignments: [.horizontal])`, include it in the same `session.run([hand, world, plane])`, and consume its anchor updates in a generation-keyed task. Translate `PlaneAnchor` into `DetectedTableSurface` immediately at the boundary. Do not leak `PlaneAnchor` into coordinator or game code.

Add `tablePlacement` to `LiveHandJointSession` with a default `nil` implementation for tests. The coordinator exposes detected placement for live Sheep Drop and deterministic estimated placement for Demo Mode. Reset it during cancellation/failure/completion.

- [ ] **Step 7: Verify GREEN**

Build the three targeted test classes. Expected exit 0, with no new warning beyond the existing AVPlayer notification deprecation.

- [ ] **Step 8: Commit Task 2**

```bash
git add RehabPal/Tracking/TableSurface.swift RehabPal/Tracking/HandTrackingEngine.swift \
  RehabPal/Session/RehabSessionCoordinator.swift RehabPal/Session/RehabSessionContracts.swift \
  RehabPalTests/TableSurfaceTests.swift RehabPalTests/HandTrackingEngineTests.swift \
  RehabPalTests/RehabSessionCoordinatorTests.swift
git commit -m "Add shared table surface tracking"
```

---

### Task 3: Five-Fingertip Sheep Drop State Machine

**Files:**
- Create: `RehabPal/Features/SheepDrop/SheepDropSession.swift`
- Create: `RehabPalTests/SheepDropSessionTests.swift`
- Modify: `RehabPalTests/JointFrameTests.swift` only if a reusable synthetic-frame helper belongs there.

**Interfaces:**
- Consumes: `HandJointFrame`, `AffectedHand`, `SessionProgress`, `GameplayResult`.
- Produces: `SheepDropSession`, `SheepDropObservation`, `SheepDropEvent`, `SheepDropPhase`, and `SheepDropCommand`.

- [ ] **Step 1: Write failing pose-metric tests**

Target this API:

```swift
let metrics = FiveFingertipPose(frame: clusteredFrame, sheepPosition: sheep)
XCTAssertEqual(metrics?.tipPositions.count, 5)
XCTAssertLessThanOrEqual(metrics!.clusterRatio, 0.62)
XCTAssertLessThanOrEqual(metrics!.reachRatio, 0.75)
```

Prove missing ring/little tips, wrong hand, low confidence, implausible 3 cm/15 cm hand scales, and thumb-index-only pinch all fail pickup eligibility.

- [ ] **Step 2: Verify pose RED**

Build `SheepDropSessionTests`; expected exit 65 because the processor types do not exist.

- [ ] **Step 3: Implement pose extraction and normalization**

Add `SheepDropSession.requiredJoints` containing wrist, four knuckles, and five tips. Calculate median wrist-to-knuckle distance, centroid, maximum pairwise tip distance, normalized cluster ratio, and normalized reach ratio. Reject non-finite values and scales outside 0.04–0.14 m.

- [ ] **Step 4: Write failing pickup/carry/release tests**

Tests must demonstrate:

- close pose at `t=0` and `t=0.24` does not pick up;
- close pose at `t=0.25` emits pickup;
- sheep-to-centroid offset is preserved;
- carrying in `0.62 < clusterRatio < 0.95` remains latched;
- open pose for 0.14 s does not release;
- open pose for 0.15 s emits release;
- missing tracking emits pause/freeze, never release;
- commanded centroid is filtered with 0.08-second time constant and clamped to the safe volume.

- [ ] **Step 5: Implement pickup/carry/release state machine**

Use monotonic timestamps, reset dwell starts on invalid pose, and emit idempotent commands. Capture the carry offset only once. `pause(requiresRecalibration:)` clears partial dwell and returns a freeze/reset command while preserving completed placements.

- [ ] **Step 6: Write failing scoring/reset/result tests**

Feed released sheep observations to prove:

- no pre-release score;
- no score outside inner pen bounds;
- no score above 2.5 radii;
- no score above 0.08 m/s;
- 0.24 seconds settled does not score and 0.25 seconds does;
- duplicate frames after success cannot score twice;
- failed release resets by one second or immediately outside safe volume;
- goal 5 yields `GameplayResult(exercise: .sheepDrop, prescribedDose: 5, completedDose: 5, ...)`;
- demo result note names simulated joint observations.

- [ ] **Step 7: Implement scoring and completion**

Keep the 0.8-second success/reset delay as an event deadline owned by the pure processor. Ensure progress is always `SessionProgress(completed: drops, goal: goal, partial: graspDwellFraction)` before pickup and partial 0 otherwise.

- [ ] **Step 8: Verify Task 3 GREEN**

Build `SheepDropSessionTests` and `JointFrameTests`; expected exit 0.

- [ ] **Step 9: Commit Task 3**

```bash
git add RehabPal/Features/SheepDrop/SheepDropSession.swift \
  RehabPalTests/SheepDropSessionTests.swift RehabPalTests/JointFrameTests.swift
git commit -m "Add five-fingertip Sheep Drop processor"
```

---

### Task 4: Import and Validate the CC0 Sheep Asset

**Files:**
- Create: `RehabPal/Resources/Sheep/Sheep.usdz`
- Create: `RehabPal/Resources/Sheep/LICENSE-AND-ATTRIBUTION.txt`
- Optionally retain source: `RehabPal/Resources/Sheep/Sheep.glb`
- Modify: `RehabPalTests/AssetCatalogTests.swift`

**Interfaces:**
- Produces: bundle resource named `Sheep.usdz`, loadable by the Sheep Drop view.

- [ ] **Step 1: Write the failing asset test**

Add assertions that the test host bundle or main bundle contains `Resources/Sheep/Sheep.usdz`, contains `LICENSE-AND-ATTRIBUTION.txt`, and the attribution text contains the canonical Poly Pizza URL plus `CC0 1.0`.

- [ ] **Step 2: Verify asset RED**

Build `AssetCatalogTests`; expected failure at runtime where available, and independently verify `test ! -f RehabPal/Resources/Sheep/Sheep.usdz` returns success before import.

- [ ] **Step 3: Download from the approved canonical source**

Use Poly Pizza's published download/API link for model `rgJXF570ZK`. Record the resolved asset URL and SHA-256. Do not scrape or import a differently licensed mirror.

- [ ] **Step 4: Convert GLTF/FBX to USDZ**

Prefer installed Apple conversion tooling. Inspect available commands first (`xcrun --find usdz_converter`, Reality Converter CLI, or available USD tools). Convert without changing textures, then inspect the archive and validate it with available USD tooling. Do not invent a conversion command in provenance; record the exact successful command.

- [ ] **Step 5: Write provenance metadata**

Include model title, creator, canonical source, CC0 URL, original filename, source SHA-256, converted SHA-256, download date 2026-08-10, conversion command/tool version, and any scale/orientation adjustment applied at runtime.

- [ ] **Step 6: Verify asset GREEN**

Confirm nonzero files, inspect the USDZ archive, run `xcodebuild build-for-testing` for `AssetCatalogTests`, and compile a minimal RealityKit load reference if bundle lookup alone does not prove resource inclusion.

- [ ] **Step 7: Commit Task 4**

```bash
git add RehabPal/Resources/Sheep RehabPalTests/AssetCatalogTests.swift RehabPal.xcodeproj/project.pbxproj
git commit -m "Import CC0 sheep model"
```

Only include `project.pbxproj` if Xcode's synchronized group does not include the resource automatically.

---

### Task 5: RealityKit Sheep Drop Scene and Shared Routing

**Files:**
- Create: `RehabPal/Features/SheepDrop/SheepDropView.swift`
- Modify: `RehabPal/Session/SharedRehabImmersiveView.swift`
- Modify: `RehabPal/Session/RehabSessionCoordinator.swift`
- Modify: `RehabPal/Tracking/SyntheticMovementSource.swift`
- Modify: `RehabPalTests/ExerciseSessionTests.swift`
- Modify: `RehabPalTests/RehabSessionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `SheepDropSession`, `TablePlacement`, coordinator reset/calibration APIs, `Sheep.usdz`.
- Produces: `SheepDropView` and `.sheepDrop` immersive completion routing.

- [ ] **Step 1: Write failing routing and required-joint tests**

Assert Sheep Drop requests register `SheepDropSession.requiredJoints`, Demo Mode never starts live ARKit, completion accepts only a matching `.sheepDrop` gameplay result, and reset/calibration acknowledgement requires a usable open five-fingertip frame.

- [ ] **Step 2: Verify RED**

Build targeted `ExerciseSessionTests` and `RehabSessionCoordinatorTests`; expected exit 65 for missing view/session integration APIs.

- [ ] **Step 3: Build the reference scene**

Create one RealityKit root with `PhysicsSimulationComponent.gravity = [0, -6, 0]`. Build the 1.0 × 0.7 m table, 0.36 m grass pen, four 0.07 m fence walls, and 0.26 m spawn pad using the exact dimensions/material roles in the spec. Load `Sheep.usdz` asynchronously as the visible child of a fitted physics root.

Use a stable simple collision shape, mass 0.15 kg, static/dynamic friction 0.7/0.55, restitution 0.1, and damping 1.2. Dynamic mode applies at rest/falling; kinematic applies while held/frozen/resetting.

- [ ] **Step 4: Connect frame loop to the pure processor**

Each scene update:

- publishes `SheepDropSession.requiredJoints` to the coordinator;
- handles pending processor-reset generation exactly once;
- waits for automatic detected/estimated table placement and locks it at first pickup;
- converts the sheep center/velocity into pen-local values;
- processes the coordinator's accepted affected-hand frame;
- applies kinematic carry position, release, freeze, respawn, progress, and completion events idempotently.

Never use `DragGesture` or system entity targeting for pickup.

- [ ] **Step 5: Add HUD and deterministic Demo controls**

Display `Completed X / Goal Y`, provenance, detected/estimated table state, and exact phase copy from the spec. Demo controls feed synthetic open/cluster/carry/open frames through `SyntheticMovementSource`; they may not call progress or completion directly.

- [ ] **Step 6: Route the shared immersive view**

Add an exhaustive `.exercise(.sheepDrop)` route before assessment routes and a `finishSheepDrop(_:)` method that calls `session.finish(with: .gameplay(result))`.

- [ ] **Step 7: Verify Task 5 GREEN**

Build targeted Sheep Drop, routing, coordinator, and asset tests. Expected exit 0.

- [ ] **Step 8: Commit Task 5**

```bash
git add RehabPal/Features/SheepDrop RehabPal/Session/SharedRehabImmersiveView.swift \
  RehabPal/Session/RehabSessionCoordinator.swift RehabPal/Tracking/SyntheticMovementSource.swift \
  RehabPalTests/ExerciseSessionTests.swift RehabPalTests/RehabSessionCoordinatorTests.swift
git commit -m "Add immersive Sheep Drop game"
```

---

### Task 6: Full Integration, Review, and Acceptance Checklist

**Files:**
- Modify only files required by concrete failures discovered during this task.
- Create: `.superpowers/sdd/2026-08-10-sheep-drop-rehab-game/final-report.md`

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: compile-verified branch and a physical-acceptance checklist with explicit verified/unverified status.

- [ ] **Step 1: Run focused test-bundle build**

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/SheepDropSessionTests \
  -only-testing:RehabPalTests/TableSurfaceTests \
  -only-testing:RehabPalTests/HandTrackingEngineTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -only-testing:RehabPalTests/ExerciseSessionTests \
  -only-testing:RehabPalTests/AssetCatalogTests \
  -derivedDataPath /private/tmp/RehabPalSheepFocused CODE_SIGNING_ALLOWED=NO
```

Expected: exit 0.

- [ ] **Step 2: Run full test-bundle build and app build**

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalSheepFull CODE_SIGNING_ALLOWED=NO
xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalSheepApp CODE_SIGNING_ALLOWED=NO
```

Expected: both exit 0. Record any pre-existing warnings separately from new warnings.

- [ ] **Step 3: Attempt runtime tests only on a concrete destination**

Run `xcodebuild -showdestinations -project RehabPal.xcodeproj -scheme RehabPal`. If a concrete simulator or unlocked device is listed, execute the focused suite there. If only generic placeholders exist, record runtime XCTest as unverified without claiming it passed.

- [ ] **Step 4: Run static gates**

```bash
git diff --check
git status --short --branch
shasum -a 256 RehabPal/Resources/Sheep/Sheep.usdz
rg -n "DragGesture|targetedToAnyEntity" RehabPal/Features/SheepDrop
rg -n "Completed.*Goal|five fingertips|SIMULATED" RehabPal/Features/SheepDrop RehabPal/Views
```

Expected: no Sheep Drop drag gesture, required HUD/disclosure text present, checksum matches provenance, and only the preserved pet-hunger plan remains unrelated/untracked.

- [ ] **Step 5: Review the full branch against the spec**

Inspect the entire diff from `4a443a9` to `HEAD`, not only the last task. Check every spec requirement, existing-game regressions, lifecycle ownership, event idempotence, stale-frame behavior, and asset license/provenance.

- [ ] **Step 6: Write the final report**

Record commit list, exact verification commands/exits, runtime destination status, asset source/checksums, resolved review findings, and the physical Vision Pro checklist. Mark every physical-only item `UNVERIFIED — physical Vision Pro required` until actually exercised.

- [ ] **Step 7: Commit final integration fixes/report**

```bash
git add <only concrete integration fixes> .superpowers/sdd/2026-08-10-sheep-drop-rehab-game/final-report.md
git commit -m "Verify Sheep Drop game integration"
```

- [ ] **Step 8: Finish the development branch**

Invoke `superpowers:verification-before-completion`, then `superpowers:finishing-a-development-branch`. Present integration choices; do not merge or push automatically.
