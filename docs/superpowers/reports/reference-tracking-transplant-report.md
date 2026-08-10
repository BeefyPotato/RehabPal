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
- Legacy calibration fixtures now use a nonzero straight knuckle span and reject
  only spread above 0.020 m. Recovery and introduction media copy consistently
  instruct system pinch, drag, and release rather than five-fingertip control.
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

## Physical regression follow-up

- Production tracking now creates a fresh `ARKitSession`, hand provider, world
  provider, and plane provider for every start generation. Stop, cancellation,
  and supersession cancel update tasks, stop the prior session, and discard all
  prior provider objects before another run, preventing ARKit provider reuse on
  the second exercise. Injected boundaries remain available for tests; lifecycle
  regressions prove start-stop-start separation and stale-stream rejection.
- Live Balance polls the coordinator source on each RealityKit render update.
  Unique frame chronology still gates calibration, scoring, and resets, while a
  render-cadence state retains the newest full reference quaternion delta and
  reapplies the unchanged 0.08 smoothing step every render. This matches test8-2
  cadence and explains the previously delayed ball response without adding a
  non-reference physics wake workaround.
- The retained Balance delta is explicitly cleared on every non-active route
  (including brief loss/failure/navigation) and when a long-loss processor reset
  begins. Confirmation cannot resume tray movement from a stale pre-loss target;
  a fresh unique post-recovery frame must retain a new delta first.
