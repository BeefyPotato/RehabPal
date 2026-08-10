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
- Introduction and HUD copy now describe pinch, drag, and release.

## Verification

- RED witnessed for missing anchor-transform storage and anchor-relative/reference-pose APIs.
- Mutation tests cover anchor-versus-wrist orientation, exact pose rejection, full
  quaternion slerps, direct Sheep pickup/carry/release commands, and no inferred
  release on missing joints.
- `xcodebuild build-for-testing` for generic visionOS Simulator: passed.
- `xcodebuild build` for generic visionOS Simulator: passed.
- `git diff --check`: passed.

## Remaining physical verification

No Vision Pro runtime claim is made. On-device follow-up should confirm targeted
entity acquisition, comfortable drag reach, release physics, and perceived tray
rotation under the prescribed affected hand.
