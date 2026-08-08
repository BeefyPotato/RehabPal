# RehabPal One-Shot Demo Design

## Purpose

Build a repeatable visionOS demonstration of RehabPal's daily hand-rehabilitation loop. The demo must show why spatial interaction and hand tracking are useful while remaining reliable enough for a live presentation.

The product supports clinician-prescribed rehabilitation. It does not diagnose conditions, prescribe treatment, infer medication dosage, measure grip force, or replace a physiotherapist.

## Demo Success Criteria

- A user can understand and complete the flow without a manual.
- The medication gate, both exercises, assessment, symptom check, report, and pet reward are demonstrated every demo day.
- Both exercises visibly depend on Vision Pro hand tracking.
- Targets and doses come from a hard-coded clinician prescription rather than patient calibration.
- Assessment measurements use fixed conditions and remain separate from adaptive gameplay measurements.
- The demo can recover from hand-tracking instability without bypassing product gates.
- No backend, database, authentication, CloudKit, or network service is required.
- Placeholder assets are legally redistributable in a public GitHub repository and easy to replace.

## Scope

### Included

- Minimal visionOS SwiftUI application.
- `RealityKitContent` package for replaceable placeholder assets.
- Home page with Recovery Pet and daily progress.
- Medication gate.
- Hard-coded physiotherapist prescription.
- Balance Platform game.
- Squeeze Buddy game.
- Daily fixed-condition assessment.
- Post-session symptom check.
- On-screen after-care report.
- Recovery Pet feeding and full-for-today state.
- Recovery streak presentation using fixture history.
- Reset Demo Day control.
- Real ARKit hand tracking plus a clearly disclosed demo fallback.
- Unit tests and complete device/fallback walkthroughs.

### Excluded

- Patient calibration.
- Backend storage or synchronization.
- Clinician portal or prescription editor.
- Authentication or multi-user accounts.
- PDF report export or secure sharing.
- Grip-force measurement.
- Diagnosis, treatment recommendations, or autonomous progression.
- Broad exercise library, full-body tracking, social features, or complex reward economy.

## Daily Experience and State Gating

The app uses a deterministic state machine:

`Home -> Medication Gate -> Daily Routine -> Both Exercises Complete -> Daily Assessment -> Symptom Check -> After-Care Report -> Feed Pet -> Full for Today`

### Rules

1. The app launches on the Home page, showing the Recovery Pet, daily routine status, streak, and Start Daily Routine action.
2. Starting the routine presents: "Have you taken your prescribed medication?"
3. Answering **No** keeps the routine locked and displays neutral guidance to follow the prescribed medication instructions. The app gives no dosing or medical advice.
4. Answering **Yes** unlocks Balance Platform and Squeeze Buddy.
5. The two exercises may be completed in either order.
6. Each exercise ends automatically when its prescribed dose is reached.
7. Daily Assessment remains locked until both exercises are complete.
8. Symptom Check remains locked until Daily Assessment is complete.
9. After-Care Report remains locked until the symptom check is submitted.
10. Feeding the Recovery Pet remains locked until the report has been viewed.
11. Feeding the pet changes it to a visible full-for-today state and disables additional rehabilitation rewards.
12. Reset Demo Day restores the medication gate, exercise progress, assessment, symptom check, report-viewed state, and pet feeding state. It retains prescription and comparison fixtures.

Unlike the source product document's five-completed-day cadence, this one-shot demo runs the standardized assessment every demo day so the complete story can always be presented.

## Physiotherapist Prescription

The patient does not calibrate in the demo. A bundled `Prescription` fixture represents values previously configured by a physiotherapist:

- Affected hand.
- Wrist directional targets and safe bounds.
- Balance Platform corrections per direction.
- Balance Platform centre-zone tolerance and hold duration.
- Squeeze Buddy repetition count.
- Closing, hold, and reopening timing.
- Finger closure and reopening thresholds.
- Assessment wrist target ranges.
- Assessment attempts per direction.
- Assessment squeeze repetition count.
- Symptom follow-up thresholds.

Patients cannot edit these values. Game visuals can become more forgiving inside the prescribed bounds, but the prescribed range and dose never expand automatically.

## Hand-Tracking Architecture

One `HandTrackingEngine` consumes ARKit hand-anchor updates. For each tracked hand it combines the anchor transform and skeleton joint transforms to produce world-space joint samples.

Derived observations include:

- Approximate MCP, PIP, and DIP flexion angles from adjacent segment vectors.
- Wrist/hand orientation relative to the prescribed neutral reference.
- Whole-hand opening and closing progress.
- Thumb-to-fingertip distances.
- Joint and hand trajectory over time.
- Velocity, controlled pacing, and a transparent smoothness estimate.
- Tracking quality based on tracked-anchor state, sample continuity, and missing-sample duration.

These are app-estimated movement measures, not clinical goniometer values, diagnoses, force measurements, or proof of correct treatment form.

### Engine Modes

- **Game mode:** uses the prescribed ROM envelope and permits forgiving visual tolerances. It records gameplay performance for feedback and engagement.
- **Assessment mode:** uses fixed targets, timing, attempt counts, and tolerances. It records standardized assessment values for baseline-to-previous-to-current comparisons.

Both modes use the same joint sampling, angle calculations, movement detectors, and scoring utilities. They store results in separate model types.

### Tracking Loss

When a hand anchor is not tracked or samples exceed the missing-data threshold:

- Pause active timers, scoring, and repetition transitions.
- Show "Hands temporarily not visible."
- Resume smoothly when valid tracking returns.
- Do not count the interruption as a failed attempt.
- Record tracking-quality notes in session and assessment results.

## Hybrid Demo Fallback

A discreet demo settings panel can enable a clearly labeled fallback mode on unsupported simulator environments or during hardware instability. The fallback injects synthetic movement observations through the same detector and scoring interfaces used by real tracking.

It must not mutate the app directly into arbitrary completed screens. Medication, exercise completion, assessment, symptom, report, and pet gates remain enforced by the same state machine.

## Balance Platform

Balance Platform uses RealityKit primitives only. No downloaded models are used for its platform, ball, centre target, boundaries, or direction indicators.

### Interaction

- A ball rests on a low-stress platform with a centre target.
- The platform requests forward, backward, left, and right wrist corrections.
- Wrist orientation moves the ball toward the centre.
- The ball is constrained to the platform and cannot fall.
- A correction completes when the ball remains in the centre target for the prescribed hold duration.
- The game ends automatically at the prescribed directional dose.

### Fair Direction Scheduling

The scheduler creates equal counts for all four directions, shuffles their order, and prevents the final dose from being directionally biased. Tests verify the distribution for all supported dose fixtures.

### Measurements

- Direction completion.
- Centre accuracy and time in target.
- Correction time without treating faster as inherently better.
- Overshoot and undershoot.
- Usable directional ROM.
- Controlled pacing and smoothness.
- Tracking quality.

## Squeeze Buddy

Squeeze Buddy uses a physical stress ball for tactile resistance and overlays playful visual feedback. Vision Pro observes hand closing and release; it does not measure or infer grip force.

### Rep Detector

The detector is a hysteretic state machine:

`Open -> Closing -> Held -> Reopening -> Open/Rep Complete`

- A rep begins only from a valid prescribed open state.
- Closing must cross the prescribed joint-pattern threshold.
- The closed state must remain valid for the prescribed hold duration.
- A rep completes only after the hand crosses the reopening threshold.
- Separate close/reopen thresholds and minimum dwell times prevent noisy samples from double-counting.
- Tracking loss pauses the detector in its current phase.
- The game ends automatically at the prescribed repetition count.

The placeholder character or face reacts to the normalized closing phase, held state, successful rep, and completion.

## Daily Assessment

Daily Assessment unlocks after both games and uses fixed conditions every demo day.

### Wrist Direction and Control

- Neutral-centre hold.
- Forward, backward, left, and right fixed targets.
- Two attempts per direction for the demo.
- Fixed target range, hold, return-to-centre rule, and timing windows.
- Measures directional ROM, target completion, centre accuracy, overshoot/undershoot, smoothness, movement time, directional asymmetry, and attempt consistency.

### Hand Closing and Release

- Five standardized repetitions around the same stress-ball placement.
- Two-second close, one-second hold, and two-second release cue.
- Measures app-estimated finger flexion/extension, close/release completion, smoothness, tempo accuracy, consistency, first-to-last change, digit-specific limitation, and tracking quality.
- Does not measure strength.

Assessment results remain separate from gameplay results and drive the report's formal baseline, previous, and current comparison.

## Symptom Check and Follow-Up Flag

After assessment, collect:

- Current pain or discomfort.
- Whether pain increased compared with before the routine.
- Stiffness.
- Perceived difficulty.
- Catching or locking where relevant.

These values are explicitly patient-reported and never inferred from tracking. A hard-coded clinician threshold can add a "Review with physiotherapist" flag. The app does not diagnose the cause or alter the prescription.

## After-Care Report

The report is an on-screen demo backed by fixture history plus today's assessment, gameplay, symptom, and tracking-quality results.

It distinguishes:

- **Assessment metrics:** fixed-condition values used for formal comparison.
- **Gameplay metrics:** adaptive session-performance evidence.
- **Patient-reported metrics:** symptoms and perceived difficulty.

The patient-facing summary includes:

- Baseline, previous, and current wrist control/ROM summary.
- Baseline, previous, and current finger-closure consistency.
- Both exercises and prescribed doses completed.
- Session/streak fixture history.
- Symptom comparison.
- Tracking-quality note.
- Neutral follow-up flag when thresholds are crossed.

Language remains descriptive, such as "movement range is similar to your previous check," and avoids treatment conclusions.

## Recovery Pet Loop

- The Home page makes the Recovery Pet the primary adherence cue.
- Viewing the completed report unlocks a food/treat interaction.
- The pet reacts, eats, and becomes visibly happy and full.
- Full-for-today messaging celebrates stopping at the prescribed dose.
- Additional repetitions cannot earn more food.
- Fixture history presents a gentle recovery streak without punishment, sickness, or lost permanent progress.

## UX Pages

1. **Home / Recovery Pet:** pet, daily completion, streak, Start Daily Routine, and discreet demo settings.
2. **Medication Gate:** yes/no question and locked neutral reminder state.
3. **Daily Routine:** two exercise cards with prescribed dose, status, and order-independent launch actions.
4. **Exercise Introduction:** short spatial preview, dose, and safety guidance.
5. **Balance Platform:** primitive scene, direction cue, tracking status, and progress.
6. **Squeeze Buddy:** stress-ball placement, phase cue, animated feedback, tracking status, and repetition progress.
7. **Daily Assessment:** fixed wrist targets followed by paced close/hold/release checks.
8. **Symptom Check:** compact patient-reported controls.
9. **After-Care Report:** concise comparison, adherence, symptom, tracking, and follow-up information.
10. **Pet Reward / Full for Today:** feeding interaction, reaction, and anti-overtraining completion message.

Use passthrough, seated/stationary-first placement, large controls, a short first-use movement preview, restrained audio cues, and minimal in-exercise text. Never place targets behind the user or require leaning, stepping, or unsafe reach.

## Placeholder 3D Assets

Find and integrate:

- One cute virtual pet appropriate for RehabPal.
- One simple food or treat asset.
- Optionally one pet bed or home asset.

### Licensing and Selection Rules

- Prefer CC0 or public-domain assets.
- The license must explicitly permit redistribution inside a public GitHub repository.
- Do not use ripped game assets, copyrighted character models, or assets with unclear licensing.
- Prefer USDZ or USD.
- GLB, GLTF, FBX, or OBJ may be used only when the source license permits redistribution and conversion to a RealityKit-compatible USDZ/USD succeeds.
- Preserve original license files when supplied.

### Integration Rules

- Put assets in the existing `RealityKitContent` package once the minimal project creates it.
- Group or name them clearly as placeholders.
- Load them through a small asset catalog so later replacements do not affect session or game logic.
- Provide primitive fallbacks for every placeholder so missing files do not break the demo.
- Do not restructure unrelated project areas.
- Balance Platform models are excluded from asset search and are generated with RealityKit primitives.

### Attribution Record

Create `ASSET_ATTRIBUTION.md` with one entry per included asset:

- Asset name and purpose.
- Original source URL.
- Creator.
- Exact license and license URL.
- Required attribution text, or "None required" for CC0.
- Downloaded source format.
- Conversion steps and tools, if any.
- Local path in `RealityKitContent`.
- Date accessed.

Do not commit any candidate asset until these fields have been verified from the original source page.

## Project Architecture

Create a minimal visionOS SwiftUI app and `RealityKitContent` package because the repository currently contains only `README.md`.

Responsibilities are separated as follows:

- `AppState`: daily state machine, eligibility queries, and reset behavior.
- `Prescription`: immutable clinician-provided demo settings.
- `DemoData`: fixture prescription, historical assessments, adherence, and report inputs.
- `HandTrackingEngine`: ARKit session lifecycle and normalized joint observations.
- Movement math utilities: transforms, segment vectors, angles, distance, velocity, and smoothness.
- Wrist detector: neutral reference and directional target completion.
- Squeeze detector: close/hold/reopen hysteresis.
- Balance Platform feature: direction schedule, primitive scene, scoring, and result.
- Squeeze Buddy feature: object placement, feedback animation, scoring, and result.
- Assessment feature: fixed wrist and squeeze protocols and result.
- Symptom feature: patient-reported result and threshold evaluation.
- Report feature: merges distinct data sources into descriptive presentation values.
- Asset catalog: replaceable placeholder lookup and primitive fallbacks.

Views consume observable feature/state models; they do not write completion flags directly.

## Data and Persistence

- Prescription, baseline, previous assessment, adherence history, and report history are bundled Swift fixtures.
- Today's progress and results live in memory.
- Reset Demo Day clears only today's state.
- No database, file persistence, networking, analytics, or external service is used.

## Failure Handling

- Missing hand-tracking permission or unsupported environments explain the limitation and offer labeled demo fallback.
- Tracking loss pauses rather than penalizes.
- Missing model assets use primitive fallbacks.
- Invalid state transitions remain locked.
- Insufficient tracking yields unavailable or low-confidence report values rather than fabricated measurements.
- Asset conversion failure rejects that candidate and keeps the primitive fallback.

## Verification Strategy

### Unit Tests

- Every allowed and forbidden `AppState` transition.
- Medication No blocks the routine; Yes unlocks it.
- Both exercise completion orders unlock assessment only after the second completion.
- Assessment, symptom, report-viewed, and pet gates.
- Reset Demo Day clears daily state and preserves fixtures.
- Joint-vector angle calculations with known poses.
- World-transform composition.
- Wrist target classification and tolerance behavior.
- Squeeze hysteresis, dwell timing, double-count prevention, and tracking-loss pause/resume.
- Equal Balance Platform direction distribution.
- Fixed Assessment mode parameters versus forgiving Game mode parameters.
- Follow-up threshold evaluation.
- Report separation of assessment, gameplay, and patient-reported data.
- Asset lookup and primitive fallback.

### Integration and Manual Verification

- Simulator/fallback walkthrough of the complete daily state machine.
- Device walkthrough using live hand tracking.
- Medication No branch and recovery to Yes.
- Both exercise orders.
- Mid-repetition tracking loss and resume.
- Assessment fixed-condition repeatability.
- Low-confidence report labeling.
- Follow-up flag threshold crossing.
- Pet feeding and full-for-today lock.
- Reset Demo Day returns to the initial medication gate.
- Placeholder model load and deliberate missing-model fallback.

## Implementation Order

1. Scaffold the minimal visionOS app, tests, and `RealityKitContent` package.
2. Implement data models and the tested daily state machine.
3. Implement fixtures, Home, medication gate, and Daily Routine shell.
4. Implement movement math, tracking engine, and synthetic observation fallback.
5. Implement Balance Platform with primitives and a balanced scheduler.
6. Implement Squeeze Buddy and hysteretic repetition detection.
7. Implement the fixed daily assessment.
8. Implement symptom check, follow-up threshold, and after-care report.
9. Implement Recovery Pet reward, full-for-today state, and demo reset.
10. Research, license-check, convert, attribute, and integrate placeholder assets.
11. Run unit, fallback-flow, asset, and device verification.

