# Reference Tracking Transplant Report

Date: 2026-08-10

## Implemented

- Balance frames retain ARKit's hand-anchor transform separately from the wrist joint.
- Balance calibration matches `test8-2`: four ordered knuckles, nonzero span,
  horizontal-axis and Y-spread limits, endpoint-line straightness, and 25 unique
  consecutive frames from the prescribed hand.
- Neutral and movement use the full hand-anchor quaternion. The tray applies the
  reference 0.6 target slerp and 0.08 per-frame smoothing without decomposition,
  clamping, or yaw removal.
- Live Sheep Drop uses test 9-3's targeted zero-distance drag on the sheep collision
  root. Pickup/carry are kinematic; release is dynamic; existing physics settlement,
  scoring, goals, lifecycle, assisted progress, and reporting remain in place.
- Live Sheep Drop no longer consumes fingertip samples. Demo/assisted progress retains
  its deterministic synthetic processor path.
- A tracking interruption safely invalidates a held system drag. The sheep stays
  frozen while paused, resumes in waiting-for-drag state, and ignores the stale
  gesture end without releasing or scoring.
- Sheep long-loss recalibration uses a fresh affected-hand wrist/anchor frame rather
  than the superseded five-fingertip pose.
- Live Sheep outcomes explicitly identify RealityKit targeted system pinch/drag and
  physics; they no longer claim five-fingertip tracking.
- Introduction and HUD copy now describe pinch, drag, and release.

## Verification

- RED witnessed for missing anchor-transform storage and anchor-relative/reference-pose APIs.
- Mutation tests cover anchor-versus-wrist orientation, exact pose rejection, full
  quaternion slerps, direct Sheep pickup/carry/release commands, and no inferred
  release on missing joints. Additional review regressions cover brief/long interrupted
  drags, stale drag end, wrist-only Sheep recalibration, and exact 0.020 m accepted
  versus 0.0201 m rejected calibration spread on nonzero straight fixtures, plus
  explicit zero-span rejection.
- `xcodebuild build-for-testing` for generic visionOS Simulator: passed.
- `xcodebuild build` for generic visionOS Simulator: passed.
- `git diff --check`: passed.
- Focused simulator execution for JointFrame/Sheep/Coordinator was bounded and
  interrupted after 44 seconds while the visionOS test runner waited to materialize;
  it produced no test-case result. Compile/build evidence above remains authoritative.

## Remaining physical verification

No Vision Pro runtime claim is made. On-device follow-up should confirm targeted
entity acquisition, comfortable drag reach, release physics, and perceived tray
rotation under the prescribed affected hand.
