# Joint-Tracked Rehab Games Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Platform Ball with the `test8-2` calibrated physics game and give every current game/diagnostic affected-hand, joint-specific tracking with visible prescribed progress.

**Architecture:** One mixed immersive space hosts a shared ARKit joint-frame source. Pure per-experience processors turn immutable frames into progress/results, while a coordinator owns lifecycle, live-first fallback, and routing into the existing daily flow.

**Tech Stack:** Swift 5, SwiftUI, Observation, ARKit, RealityKit, XCTest, visionOS 27

## Global Constraints

- Work only on `feature/game-enhancements`; preserve unrelated untracked files.
- Enforce `Prescription.affectedHand` for calibration and scoring.
- Live tracking is the default; demo mode is explicit and simulated results are labeled.
- Tracking loss preserves completed reps, discards partial reps, and requires recalibration after two seconds.
- Balance pitch and roll clamp independently to 20 degrees and ignore yaw.
- Squeeze uses grasp-pose inference and renders no fake ball mesh.
- Every rep/attempt experience shows completed and prescribed goal counts.

---

### Task 1: Joint-frame tracking core

**Files:** Modify tracking models and tests under `RehabPal/Tracking` and `RehabPalTests`.

- [ ] Write failing tests for app-owned joints, affected-hand filtering, frame confidence, calibration, relative wrist orientation, yaw removal, and tilt clamping.
- [ ] Run the focused tests and confirm expected failures.
- [ ] Implement immutable joint frames, ARKit mapping, synthetic frames, neutral calibration, and pure movement math.
- [ ] Run focused and existing movement tests; refactor with all tests green.
- [ ] Commit the tracking core.

### Task 2: Shared session contracts and immersive lifecycle

**Files:** Modify the app entry point, content routing, and add focused session/coordinator files and tests.

- [ ] Write failing tests for session requests, progress, outcomes, live/demo provenance, tracking loss, and result routing.
- [ ] Run the focused tests and confirm expected failures.
- [ ] Implement the shared coordinator and mixed immersive-space registration, retaining window navigation.
- [ ] Implement live-first startup with Retry and explicit Demo Mode on failure; never switch silently.
- [ ] Run focused and state/router regression tests, then commit.

### Task 3: Physics Balance Platform

**Files:** Replace the existing balance session/view and extend exercise tests.

- [ ] Write failing tests for 10 prescribed targets, calibration, target scoring, resets, tracking pause, yaw rejection, and independent 20-degree clamps.
- [ ] Run tests and confirm expected failures.
- [ ] Port the `test8-2` tray, walls, hole, dynamic ball, damping, spawn/reset, and per-frame physics behavior into the shared immersive session.
- [ ] Add the common `Completed X / Goal Y` HUD and measured `GameplayResult`.
- [ ] Run tests/build and commit.

### Task 4: Inferred real-ball Squeeze Buddy

**Files:** Replace the squeeze presentation/processor and extend movement/exercise tests.

- [ ] Write failing tests for stable cupped-grasp gating, 2.5–6.5 cm radius bounds, 18% stability, face position, closure normalization, phase counting, interruption reset, and exact goal completion.
- [ ] Run tests and confirm expected failures.
- [ ] Implement affected-hand grasp inference and viewer-facing eyes/mouth overlay without a virtual ball.
- [ ] Feed normalized closure through close-hold-reopen and add phase plus `Completed X / Goal Y` HUD.
- [ ] Run tests/build and commit.

### Task 5: Automated wrist and finger diagnostics

**Files:** Replace assessment session/view logic and extend assessment tests.

- [ ] Write failing wrist tests for sequence, 20-degree target, 5-degree tolerances, 0.5-second hold, neutral return, score formula, counters, and tracking loss.
- [ ] Write failing finger tests for flexion conversion, stable extension, 15-degree excursion, 8-degree return, thumb 25% opposition, extrema, confidence, and ten-attempt progress.
- [ ] Run focused tests and confirm expected failures.
- [ ] Implement both processors and shared diagnostic HUD, returning actual wrist/finger results.
- [ ] Run assessment/report regressions and commit.

### Task 6: Prescription, results, integration, and verification

**Files:** Modify prescription/result/state/report integration and affected UI/tests.

- [ ] Write failing tests proving every goal comes from Prescription and demo outcomes remain labeled simulated.
- [ ] Replace fixture completion and obsolete correction-based balance configuration with measured outcomes and explicit goal/tolerance fields.
- [ ] Run the full test suite and build for visionOS.
- [ ] Review the complete diff against the design, document any physical-device-only checks, and commit final integration.
