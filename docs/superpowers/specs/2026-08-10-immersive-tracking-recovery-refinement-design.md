# Immersive Tracking Recovery Refinement Design

**Date:** 2026-08-10

**Status:** Approved

## Goal

Prevent random global pauses when a nonessential hand joint is briefly obscured, keep every game measurement safe, make Sheep Drop reachable using the placement logic of `/Users/event/Downloads/test 9-3`, and replace overlapping recovery prompts with one compact immersive status panel.

## Shared Tracking Policy

The coordinator distinguishes two conditions:

1. **Prescribed-hand presence:** the affected-hand wrist is tracked in a fresh frame.
2. **Experience measurement readiness:** the processor-specific joints required for the current phase are tracked.

Only loss of prescribed-hand presence enters the common global tracking-loss timer. A missing non-wrist measurement joint does not change `RehabSessionPhase` to paused. Instead, the active processor receives an unusable measurement observation, freezes/discards only its partial phase, and shows local guidance.

Global behavior:

- fresh prescribed-hand wrist present: session remains active;
- wrist missing/stale/wrong-hand for less than two seconds: compact recovery state, physics/measurement frozen, completed progress preserved;
- wrist missing for at least two seconds: processor reset generation and recalibration required;
- recovery never treats missing fingers as movement or release;
- complete repetitions/placements/attempts remain preserved;
- each processor publishes only phase-specific measurement requirements for its own local readiness checks.

The coordinator's frame acceptance floor is wrist-only for immersive hand-presence monitoring. Processors remain responsible for stricter joint sets and must never count from incomplete inputs.

## Per-Experience Measurement Readiness

### Balance

- Neutral phase: wrist plus index/middle/ring/little knuckles.
- Active phase: wrist only.
- Missing calibration knuckle resets neutral-capture progress locally.
- Missing wrist triggers global loss.
- Tracking otherwise follows the 25-frame neutral and calibrated wrist-delta logic from `test8-2`.

### Sheep Drop

- Waiting/forming grasp: wrist, five fingertips, and four scale knuckles are needed to evaluate a pickup candidate.
- Carrying: wrist plus five fingertips and scale knuckles are needed to update the carry pose or detect open-hand release.
- Partial fingertip/knuckle loss freezes the sheep kinematically and clears pickup/release dwell; it does not enter global pause while wrist remains fresh.
- Missing data can never be interpreted as release.
- Wrist loss enters global loss and freezes the sheep.
- Long wrist loss resets the sheep to spawn and clears partial state.

### Squeeze

- Grasp discovery and rep phases require the exact joints used by `SqueezeSession` metrics.
- Partial finger occlusion clears grasp stability and the current close/hold/reopen dwell while preserving completed reps.
- The inferred face is hidden while measurement readiness is unavailable.
- The session remains globally active if the wrist is fresh.
- Missing wrist enters global loss.

### Wrist diagnostic

- Require the wrist plus only the reference joints used for current wrist-angle measurement.
- Missing non-wrist reference data invalidates the current hold/attempt locally without pausing the whole session.
- Missing wrist enters global loss.

### Finger diagnostic

- Require wrist/reference plus joints for the currently measured digit only.
- Other digits may be obscured without pausing.
- Missing current-digit data discards the partial attempt locally.
- Missing wrist enters global loss.

## Sheep Drop Reachability

Match `test 9-3` placement behavior:

- default center: `(0, 0.73, -0.55)` m;
- a suitable detected horizontal table supplies only its world Y height;
- scene X remains `0` and Z remains `-0.55`;
- plane rotation and plane-anchor X/Z center are ignored;
- detected height is clamped to `0.60...0.95` m;
- if detection times out, use Y `0.73`;
- lock the scene transform after placement and never move it during a repetition/session.

This intentionally differs from the earlier full-plane-transform behavior, which could place a large table anchor's center out of reach.

The existing five-fingertip cluster pickup and open-hand release processor remains. Do not replace it with `DragGesture`.

## Recovery UI

The window-level centered `SessionLifecycleCard` is not shown for immersive tracking loss. Each immersive experience renders a shared compact `ImmersiveRecoveryPanel` above its HUD.

The panel shows:

- `Hand tracking lost` for brief wrist loss;
- `Recalibration required` after the two-second threshold;
- `Completed X / Goal Y`;
- one recovery instruction specific to the active experience;
- a Recalibrate button only when `canConfirmRecalibration` is true;
- a Back to Routine action that closes the immersive session safely.

When the recovery panel is visible, the normal phase instruction is hidden. The HUD and panel may not occupy the same vertical region. Game entities remain visible but frozen.

Failure/startup permission cards may remain window-level because no game HUD is active yet.

## Navigation

- Every exercise introduction includes Back, returning to Today's Routine.
- Back never returns to initial Home/Check In.
- If no immersive session is active, Back clears selection only.
- If a session is starting/active/paused, Back cancels the coordinator, dismisses the immersive space, clears AppState authorization, and returns to the routine.
- Each immersive recovery panel exposes Back to Routine using that same teardown path.
- Diagnostics retain their existing workflow navigation unless explicitly canceled through the recovery panel.

## Testing

Tests must prove:

- a fresh wrist with missing nonessential joints does not globally pause;
- missing wrist does globally pause and reaches recalibration after two seconds;
- Balance switches calibration joints to wrist-only;
- Sheep partial tip loss freezes without release or global pause;
- Squeeze partial finger loss discards partial rep and hides face without global pause;
- current-digit diagnostic loss discards only that attempt;
- other-digit loss does not block current finger diagnostic;
- table X/Z is always `(0, -0.55)` despite arbitrary plane-anchor X/Z/rotation;
- detected plane Y is used and fallback Y is 0.73;
- recovery panel replaces normal instruction rather than overlapping;
- Back from each exercise intro returns to routine;
- Back from recovery closes the immersive session and clears authorization.

Full visionOS test-bundle and app builds are required. Physical Vision Pro acceptance must verify partial occlusion behavior, reachable Sheep placement, non-overlapping recovery UI, and safe Back teardown.
