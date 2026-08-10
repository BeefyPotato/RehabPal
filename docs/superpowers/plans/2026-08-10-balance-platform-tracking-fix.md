# Balance Platform Tracking Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Balance Platform match `test8-2` neutral/wrist tracking, stop knuckle-occlusion pauses during play, restore the Begin gate, and lock the tray at a comfortable viewer-relative height.

**Architecture:** Keep RehabPal's shared coordinator and app-owned frames, but move calibration chronology and phase-specific required joints into `BalanceSession`. Add a pure placement helper and let `BalancePlatformView` capture one viewer-relative transform, publish calibration joints only until neutral is captured, then publish wrist-only requirements.

**Tech Stack:** Swift 5, SwiftUI, RealityKit, ARKit app-owned joint frames, Observation, XCTest, Xcode visionOS build tools.

## Global Constraints

- Behavioral tracking reference: `/Users/event/Downloads/test8-2/test8/HandTrackingModel.swift` and `PalmPlaneImmersiveView.swift`.
- Calibration requires 25 consecutive unique valid prescribed-hand frames.
- Calibration joints are wrist plus index/middle/ring/little knuckles; active play requires wrist only.
- Existing yaw removal and independent ±20° pitch/roll clamp remain unchanged.
- Tray position is viewer Y minus 0.25 m, clamped to 0.72...1.20 m, X 0, Z -1.0; fallback `(0, 0.9, -1.0)`.
- Tray/HUD placement locks when the RealityKit scene initializes and never follows later head movement.
- Balance must not launch ARKit/immersive space before Begin is pressed.
- Brief wrist loss preserves neutral; loss at least two seconds clears neutral and requires 25 new valid frames.
- Preserve completed repetitions and discard only the active ball attempt on loss.
- Existing Squeeze, Sheep Drop, diagnostics, explicit Demo Mode, and reporting behavior remain unchanged.
- Preserve unrelated untracked `docs/superpowers/plans/2026-08-09-pet-hunger.md`.

---

### Task 1: Restore the Balance Introduction Begin Gate

**Files:**
- Modify: `RehabPal/ContentView.swift`
- Modify: `RehabPal/Views/ExerciseDemoView.swift`
- Test: `RehabPalTests/ContentViewTests.swift`

**Interfaces:**
- Produces: `ExerciseKind.requiresExplicitBegin == true` for Balance, Squeeze, and Sheep Drop.
- Preserves: selecting an exercise shows its introduction; only Begin creates `currentRequest`.

- [ ] **Step 1: Write failing launch-gate tests**

Add behavior tests proving `ContentView.sessionRequest(for: .balance, hasBegun: false, prescription:)` is nil, becomes the prescribed request after Begin, and cancellation remains nil. Assert all three exercises use explicit Begin.

- [ ] **Step 2: Verify RED**

Run targeted generic `build-for-testing` for `ContentViewTests`; expected exit 65 or failing assertion because Balance currently launches immediately.

- [ ] **Step 3: Implement the minimal gate**

Replace Squeeze-specific `squeezeStarted` naming with exercise-neutral `exerciseStarted`. Initialize it false for every selected exercise, set it from the introduction Begin action, and require it before `currentRequest` exists. Initialize `ExerciseDemoView.started` false for Balance.

- [ ] **Step 4: Verify GREEN and commit**

Run focused simulator tests where available plus generic test-bundle build. Commit:

```bash
git add RehabPal/ContentView.swift RehabPal/Views/ExerciseDemoView.swift RehabPalTests/ContentViewTests.swift
git commit -m "Restore Balance introduction gate"
```

---

### Task 2: Reference-Style Neutral Calibration and Dynamic Joint Requirements

**Files:**
- Modify: `RehabPal/Features/Balance/BalanceSession.swift`
- Modify: `RehabPal/Tracking/JointFrame.swift` only if a pure neutral-pose predicate is needed.
- Modify: `RehabPalTests/ExerciseSessionTests.swift`
- Modify: `RehabPalTests/JointFrameTests.swift` only for predicate coverage.

**Interfaces:**
- Produces: `BalanceSession.calibrationFrameGoal`, `calibrationProgress`, and `requiredJoints`.
- Consumes: unique `HandJointFrame.timestamp` values and existing `WristNeutralCalibration.capture(from:)` geometry.

- [ ] **Step 1: Write failing calibration chronology tests**

Test these literal behaviors:

```swift
XCTAssertEqual(session.calibrationFrameGoal, 25)
for index in 0..<24 {
    XCTAssertEqual(session.process(frame: levelFrame(timestamp: Double(index)), ...), .waitingForCalibration)
}
XCTAssertFalse(session.isCalibrated)
_ = session.process(frame: levelFrame(timestamp: 24), ...)
XCTAssertTrue(session.isCalibrated)
```

Add tests that repeated timestamps do not increment, missing/wrong-hand/nonlevel frames reset progress, and regressed/nonfinite timestamps cannot calibrate.

- [ ] **Step 2: Verify RED**

Run targeted `ExerciseSessionTests`; expected failure because current code captures on one frame.

- [ ] **Step 3: Implement 25-frame capture**

Track the last processed calibration timestamp and consecutive valid count. Validate chronology before mutation. Keep the tray flat and return `.waitingForCalibration` for frames 1–24. Capture frame 25's wrist transform, reset the counter only when calibration is cleared, and never count one frame twice.

- [ ] **Step 4: Write failing phase-specific required-joint tests**

Assert before calibration:

```swift
XCTAssertEqual(session.requiredJoints, WristNeutralCalibration.requiredJoints)
```

After frame 25:

```swift
XCTAssertEqual(session.requiredJoints, [.wrist])
```

Prove an active frame with tracked wrist and untracked knuckles remains `.active`, while a missing wrist pauses.

- [ ] **Step 5: Implement dynamic requirements**

Expose the pure property and ensure active processing reads only the wrist once calibration exists. Do not weaken the calibration predicate.

- [ ] **Step 6: Add brief/long loss regression tests**

Prove `pause(requiresRecalibration: false)` retains `isCalibrated` and returns `.resetBall` on recovery; `pause(requiresRecalibration: true)` clears neutral/progress and requires 25 new valid frames; completed success count remains unchanged.

- [ ] **Step 7: Verify GREEN and commit**

Run serial Balance/JointFrame tests plus generic build. Commit:

```bash
git add RehabPal/Features/Balance/BalanceSession.swift RehabPal/Tracking/JointFrame.swift \
  RehabPalTests/ExerciseSessionTests.swift RehabPalTests/JointFrameTests.swift
git commit -m "Match Balance tracking to reference logic"
```

---

### Task 3: Viewer-Relative Locked Platform Placement

**Files:**
- Modify: `RehabPal/Features/Balance/BalancePlatformView.swift`
- Modify: `RehabPalTests/ExerciseSessionTests.swift`

**Interfaces:**
- Produces: `BalancePlatformPlacement.position(viewerPosition:) -> SIMD3<Float>` and a view-captured locked tray position.
- Consumes: `RehabSessionCoordinator.currentViewerPosition` once during scene initialization.

- [ ] **Step 1: Write failing placement tests**

Cover literal expected values:

```swift
XCTAssertEqual(BalancePlatformPlacement.position(viewerPosition: [0.2, 1.6, 0.1]), [0, 1.2, -1])
XCTAssertEqual(BalancePlatformPlacement.position(viewerPosition: [0, 1.1, 0]), [0, 0.85, -1])
XCTAssertEqual(BalancePlatformPlacement.position(viewerPosition: [0, 0.8, 0]), [0, 0.72, -1])
XCTAssertEqual(BalancePlatformPlacement.position(viewerPosition: nil), [0, 0.9, -1])
```

Add a pure placement-latch test showing later viewer positions do not replace the first locked value.

- [ ] **Step 2: Verify RED**

Run targeted generic build; expected missing placement type.

- [ ] **Step 3: Implement placement and latch**

Add `BalancePlatformPlacement` with exact math/clamps. In `RealityView` construction, capture one position from `coordinator.currentViewerPosition`, assign tray transform, and store it for escape checks, reset transforms, and HUD placement. Never recompute from viewer movement.

- [ ] **Step 4: Make HUD relative to tray**

Set HUD position from the locked tray center plus a fixed readable offset. Remove duplicate fixed-world tray/HUD constants.

- [ ] **Step 5: Verify GREEN and commit**

Run placement tests and generic app build. Commit:

```bash
git add RehabPal/Features/Balance/BalancePlatformView.swift RehabPalTests/ExerciseSessionTests.swift
git commit -m "Place Balance platform at viewer height"
```

---

### Task 4: View Integration, Demo Calibration, and Loss Acknowledgement

**Files:**
- Modify: `RehabPal/Features/Balance/BalancePlatformView.swift`
- Modify: `RehabPal/Tracking/SyntheticMovementSource.swift`
- Modify: `RehabPalTests/ExerciseSessionTests.swift`
- Modify: `RehabPalTests/RehabSessionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `BalanceSession.requiredJoints`, `calibrationProgress`, reset/calibration generation APIs.
- Produces: exactly-once frame processing and demo frames with distinct timestamps.

- [ ] **Step 1: Write failing view-boundary/state tests**

Add a pure chronology/lifecycle seam proving the view processes a `HandJointFrame.timestamp` once, publishes calibration requirements before neutral and wrist-only after, and does not advance calibration from render repetitions.

- [ ] **Step 2: Verify RED**

Run targeted tests; expected missing seam/dynamic behavior.

- [ ] **Step 3: Integrate dynamic requirements**

Replace unconditional `WristNeutralCalibration.requiredJoints` publication with `game.requiredJoints`. Gate processor calls by unique accepted frame timestamp. Continue physics render updates without duplicating tracking transitions.

- [ ] **Step 4: Integrate long-loss acknowledgement**

On reset generation, clear neutral and reset the ball once, acknowledge reset, publish calibration joints, feed 25 unique valid frames, then acknowledge calibration using frame 25's timestamp. Brief loss resumes wrist-only without clearing neutral.

- [ ] **Step 5: Update HUD and Demo Mode**

Show `Hold level: X / 25` during calibration. Ensure demo synthetic frames use distinct timestamps and pass through the same processor before demo drop controls enable.

- [ ] **Step 6: Verify and commit**

Run focused simulator tests with bounded duration, generic full test bundle, and app build. Commit:

```bash
git add RehabPal/Features/Balance/BalancePlatformView.swift RehabPal/Tracking/SyntheticMovementSource.swift \
  RehabPalTests/ExerciseSessionTests.swift RehabPalTests/RehabSessionCoordinatorTests.swift
git commit -m "Integrate stable Balance calibration"
```

---

### Task 5: Full Regression and Physical Acceptance Report

**Files:**
- Modify only files required by concrete regression failures.
- Create: `.superpowers/sdd/2026-08-10-balance-platform-tracking-fix/final-report.md`

- [ ] **Step 1: Run focused Balance tests**

Build and, on a concrete destination, execute Balance, ContentView, JointFrame, and coordinator tests serially. Record exact counts/exits.

- [ ] **Step 2: Run full compile gates**

```bash
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalBalanceFull CODE_SIGNING_ALLOWED=NO
xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalBalanceApp CODE_SIGNING_ALLOWED=NO
git diff --check
```

- [ ] **Step 3: Compare full runtime baseline**

If runtime finalizes, compare against the previously recorded eight unrelated failures. No new failure is acceptable. Do not claim the existing failures are fixed unless separately reproduced green.

- [ ] **Step 4: Review full diff against `test8-2` and spec**

Verify the exact 25-frame counter, reset-on-invalid pose, frame uniqueness, wrist-delta tilt, phase-specific joints, locked placement, Begin gate, and brief/long loss semantics.

- [ ] **Step 5: Write and commit report**

Mark physical Vision Pro items unverified until exercised. Commit concrete fixes and report, then invoke verification-before-completion and finishing-a-development-branch without merging or pushing automatically.
