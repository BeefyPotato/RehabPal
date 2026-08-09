# Joint-Tracked Rehab Games Design

## Goal

Replace the current Platform Ball approximation with the calibrated RealityKit physics interaction from `test8-2`, and make every current rehabilitation game and diagnostic consume affected-hand joint frames through a shared immersive tracking session.

## Architecture

RehabPal registers one mixed immersive space. A shared coordinator owns the ARKit hand session and publishes immutable, app-owned joint frames. Balance, squeeze, wrist assessment, and finger ROM each use a focused processor that consumes only the joints it needs and emits common progress and result events. Live tracking is attempted first; an explicitly labeled synthetic mode is offered only after live startup fails.

The prescribed affected hand is mandatory. A tracking interruption pauses the experience, preserves completed repetitions, discards partial motion, and requires recalibration after two seconds.

## Experiences

Balance uses a physical RealityKit tray, walls, dynamic ball, randomized hole, escape reset, and neutral calibration from four level knuckles. Relative wrist pitch and roll drive the tray; yaw is ignored and each axis is clamped to 20 degrees. The default prescription is 10 successful balls.

Squeeze renders no virtual ball. A stable cupped-hand joint envelope gates startup and estimates a center/radius for an eyes-and-mouth overlay. Closure combines finger flexion and fingertip-to-palm distance, retaining the prescribed close-hold-reopen state machine. This is labeled grasp-pose inference, not physical-object verification. The default goal is five repetitions.

Wrist assessment automatically performs center, forward, backward, left, and right attempts. Directional targets are 20 degrees with 5-degree target and off-axis tolerances, a 0.5-second hold, and a neutral return. Finger ROM automatically captures each digit from stable extension through sufficient excursion and back, including thumb-to-little-finger opposition.

Every rep-based experience displays completed and goal counts. Measured outcomes replace fixture completion; demo outcomes retain explicit simulated provenance.

## Verification

Pure processors receive deterministic synthetic joint frames for unit coverage. Tests cover chirality, calibration, tilt clamping, grasp stability, rep state machines, diagnostic scoring, tracking loss, counters, fallback, and result routing. Final verification includes the full Xcode test/build plus a physical Vision Pro acceptance pass for alignment and physics.
