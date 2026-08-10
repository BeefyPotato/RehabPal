# Balance Platform Tracking and Placement Fix Design

**Date:** 2026-08-10

**Status:** Approved design awaiting written-spec review

## Goal

Fix the Balance Platform game so it appears at a comfortable viewer-relative height, does not pause when nonessential knuckles become occluded during play, and retains the neutral wrist behavior of `/Users/event/Downloads/test8-2`.

## Confirmed Problems

1. The tray uses a fixed world transform `(0, 0.9, -1.0)`. Although this matches `test8-2`, it can appear too low for a particular wearer or seated posture.
2. RehabPal publishes `WristNeutralCalibration.requiredJoints` throughout the entire session. The coordinator therefore rejects a frame whenever any calibration knuckle is temporarily unavailable, even after neutral calibration is complete. This causes unnecessary tracking pauses.
3. Balance enters the immersive session as soon as its exercise card is selected. Its introduction view remains visible in the window, but it does not wait for the user to press Begin.
4. Neutral calibration captures on the first valid frame. The reference project requires a stable pose for approximately 25 frames, reducing accidental neutral capture.

## Selected Approach

Use reference-style phase-specific tracking:

- Before neutral capture, require the prescribed-hand wrist plus index, middle, ring, and little knuckles.
- Require the valid neutral pose for 25 consecutive accepted hand frames before calibration completes.
- After calibration, require only the prescribed-hand wrist.
- Missing knuckles after calibration must not pause the game.
- Missing/stale wrist data retains RehabPal's common tracking-loss behavior.
- Tracking loss lasting at least two seconds clears neutral and requires the four-knuckle pose again.

The affected-hand restriction, app-owned joint frames, explicit Demo Mode, progress preservation, reset acknowledgement, and common session coordinator remain unchanged.

## Introduction and Launch

Balance uses the same explicit launch gate as Squeeze and Sheep Drop:

1. Selecting Balance shows `ExerciseDemoView`.
2. The introduction explains neutral capture, viewer-relative platform placement, prescribed goal, and comfortable range.
3. The immersive session does not open and ARKit does not start until the user presses **Begin prescribed dose**.
4. Back cancels without starting a session.

The existing instruction media remains visible. Balance is no longer initialized with its introduction already marked started.

## Viewer-Relative Tray Placement

At scene startup, the game queries the coordinator's current viewer position. When a valid viewer position is available, the tray center is placed:

- 0.25 m below viewer eye height;
- 1.0 m forward along the current application world Z direction;
- centered on application world X.

The vertical result is clamped to `0.72...1.20` m to keep it within a comfortable seated/standing range. If viewer position is unavailable, use the reference fallback `(0, 0.9, -1.0)`.

The placement is captured once when the Balance RealityKit scene initializes and remains locked for the entire session. Head movement does not move the tray, ball, hole, or HUD. The HUD is positioned relative to the locked tray rather than at a separate fixed world height.

## Neutral Calibration

### Required pose

The prescribed-hand frame must contain usable transforms for:

- wrist;
- index knuckle;
- middle knuckle;
- ring knuckle;
- little knuckle.

The existing geometric pose rules remain:

- maximum knuckle height spread: 1 cm;
- finite transforms;
- prescribed hand only.

### Stability dwell

`BalanceSession` tracks consecutive valid calibration frames:

- valid pose increments the counter by one;
- invalid, missing, wrong-hand, or regressed-timestamp frame resets it to zero;
- neutral is captured only on frame 25;
- the wrist transform from frame 25 becomes the neutral orientation;
- the tray remains flat and the ball remains frozen before capture.

Each unique accepted frame may increment the counter at most once. RealityKit render frames must not repeatedly count the same `HandJointFrame.timestamp`.

The HUD shows `Hold level: X / 25` while calibrating and then switches to normal goal/progress guidance.

## Active Tracking

Immediately after calibration:

- the view changes coordinator required joints to `{ .wrist }`;
- the affected-hand wrist orientation drives calibrated pitch and roll;
- yaw remains ignored;
- pitch and roll remain independently clamped to ±20 degrees by existing movement math;
- temporary knuckle occlusion has no effect;
- a missing, low-confidence, stale, or wrong-hand wrist frame triggers the common tracking-loss path.

The game processes each accepted joint frame once. Repeated RealityKit updates with the same frame timestamp may update physics rendering but must not create tracking state transitions or duplicate calibration progress.

## Tracking Loss

### Brief wrist loss under two seconds

- freeze the ball and tray control;
- discard the current partial ball attempt;
- preserve completed hole successes;
- retain neutral calibration;
- on recovery, reset the ball to its start and resume using wrist-only requirements.

### Long wrist loss of at least two seconds

- preserve completed successes;
- discard the current ball attempt;
- clear neutral calibration and its stability counter;
- switch required joints back to wrist plus four knuckles;
- acknowledge the processor reset generation;
- obtain 25 new valid neutral frames;
- acknowledge processor calibration using the final accepted frame timestamp;
- enable the existing Recalibrate confirmation only after both acknowledgements are complete.

## Demo Mode

Demo Mode uses the same `BalanceSession` processor and 25-frame calibration gate. The synthetic source supplies 25 distinct timestamped level-hand frames before demo ball-drop controls become active. Results remain labeled simulated.

## Interfaces

Add focused pure/state interfaces rather than coupling tests to SwiftUI:

- `BalanceSession.calibrationProgress: Int`
- `BalanceSession.calibrationFrameGoal: Int` equal to 25
- `BalanceSession.requiredJoints: Set<HandJoint>` returning calibration joints before neutral and `{ .wrist }` afterward
- `BalancePlatformPlacement.position(viewerPosition:) -> SIMD3<Float>` for locked placement math
- a frame chronology guard inside `BalanceSession` so one timestamp is processed once

`BalancePlatformView` uses these interfaces to publish dynamic joint requirements and render HUD state.

## Testing

Unit tests must cover:

- introduction selection does not start Balance until Begin;
- Back does not start Balance;
- viewer height minus 0.25 m placement;
- vertical clamp at 0.72 and 1.20 m;
- fallback `(0, 0.9, -1.0)` when viewer position is unavailable;
- placement remains locked when viewer position later changes;
- calibration requires 25 unique consecutive valid frames;
- repeated timestamps do not advance calibration;
- an invalid pose resets calibration progress;
- wrong-hand frames do not calibrate;
- required joints switch from wrist plus four knuckles to wrist only;
- missing knuckles after calibration do not pause active wrist processing;
- missing wrist after calibration pauses;
- brief loss retains neutral and resets the current ball;
- long loss clears neutral and requires 25 new frames;
- completed successes survive both loss paths;
- Demo Mode uses the same calibration gate.

Regression verification must build the complete visionOS test bundle and application and must not change Squeeze, Sheep Drop, wrist diagnostic, or finger diagnostic behavior.

## Physical Vision Pro Acceptance

- Introduction remains visible until Begin is pressed.
- Tray appears approximately 25 cm below eye level and remains stationary when the head moves.
- Level pose requires a short, visible stable hold and does not capture accidentally.
- After calibration, hiding one or more knuckles while keeping the wrist tracked does not pause.
- Hiding the wrist freezes the game.
- Brief wrist recovery resets only the active ball.
- Loss longer than two seconds requires neutral capture again.
- Completed goal count remains correct through interruptions.

Physical-only checks must be reported as unverified until exercised on Vision Pro.
