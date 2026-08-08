# RehabPal One-Shot Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic, backend-free visionOS demo of RehabPal's medication-gated daily routine, two hand-tracked exercises, daily assessment, symptom check, report, and Recovery Pet reward.

**Architecture:** A tested `AppState` owns all gates and in-memory results. Feature models consume normalized `MovementObservation` values supplied by either ARKit hand tracking or a clearly labeled synthetic demo source; SwiftUI views never set completion flags directly. RealityKit primitives provide gameplay and asset fallbacks, while replaceable licensed pet assets live in a local `RealityKitContent` package.

**Tech Stack:** Swift 6, SwiftUI, RealityKit, ARKit, visionOS, XCTest

## Global Constraints

- Use the `RehabPal` project, target, scheme, and app folder.
- Keep all patient progress in memory; add no backend, persistence, authentication, analytics, or networking.
- Start at Home and ask about prescribed medication after Start Daily Routine; include no patient calibration.
- Unlock assessment and check-in only after both daily exercises complete, every demo day.
- Keep gameplay, assessment, and patient-reported metrics separate.
- Use the same detector interfaces for live hand tracking and labeled demo fallback.
- Pause timers and detectors during tracking loss; never count loss as failure.
- Use RealityKit primitives for Balance Platform, its ball, and target.
- Commit only assets whose original source page verifies redistribution rights; record them in `ASSET_ATTRIBUTION.md`.
- Use descriptive, non-diagnostic language and never claim grip-force measurement.

---

### Task 1: Normalize the project and add the test/package foundation

**Files:**
- Modify: `RehabPal.xcodeproj/project.pbxproj`
- Create: `RehabPalTests/AppStateTests.swift`
- Create: `RealityKitContent/Package.swift`
- Create: `RealityKitContent/Sources/RealityKitContent/RehabPalAssets.swift`

**Interfaces:**
- Consumes: The Xcode-generated visionOS scaffold already verified on `main`.
- Produces: A `RehabPalTests` target and local `RealityKitContent` product linked to the app.

- [ ] Merge the corrected `main` scaffold into `one-shot-prototype`, resolving in favor of the `RehabPal` project name while retaining this demo spec and plan.
- [ ] Add the test target and package references to the project, then add one intentionally failing `AppState` construction test.
- [ ] Run `xcodebuild test -project RehabPal.xcodeproj -scheme RehabPal -destination 'platform=visionOS Simulator,name=Apple Vision Pro' CODE_SIGNING_ALLOWED=NO` and verify the test fails because `AppState` does not exist.
- [ ] Add only the empty `AppState` shell needed to compile, rerun, and require the test to pass.
- [ ] Commit with `chore: prepare RehabPal demo foundation`.

### Task 2: Implement prescription fixtures and daily gating

**Files:**
- Create: `RehabPal/Models/Prescription.swift`
- Create: `RehabPal/Models/DemoData.swift`
- Create: `RehabPal/State/AppState.swift`
- Modify: `RehabPalTests/AppStateTests.swift`

**Interfaces:**
- Produces: `Prescription.demo`, `DemoData`, and `@Observable @MainActor AppState` with guarded methods `startRoutine()`, `answerMedication(_:)`, `completeExercise(_:)`, `completeAssessment(_:)`, `submitSymptoms(_:)`, `viewReport()`, `feedPet()`, and `resetDemoDay()`.

- [ ] Write failing tests for medication No/Yes, both exercise orders, assessment/symptom/report/pet gates, duplicate completion, and reset fixture preservation.
- [ ] Run the focused tests and verify each failure is caused by the missing transition.
- [ ] Implement immutable prescription fixtures and minimal guarded transitions.
- [ ] Rerun the focused suite and require zero failures.
- [ ] Commit with `feat: add deterministic daily routine state`.

### Task 3: Build movement math, detectors, and observation sources

**Files:**
- Create: `RehabPal/Tracking/MovementObservation.swift`
- Create: `RehabPal/Tracking/MovementMath.swift`
- Create: `RehabPal/Tracking/WristTargetDetector.swift`
- Create: `RehabPal/Tracking/SqueezeRepDetector.swift`
- Create: `RehabPal/Tracking/HandTrackingEngine.swift`
- Create: `RehabPal/Tracking/SyntheticMovementSource.swift`
- Create: `RehabPalTests/MovementDetectorTests.swift`

**Interfaces:**
- Produces: normalized world-space observations, `TrackingQuality`, wrist classification, squeeze hysteresis, and interchangeable live/synthetic async observation streams.

- [ ] Write failing tests with literal vectors/timestamps for angle math, transform composition, target tolerances, squeeze close-hold-reopen, double-count prevention, and tracking-loss pause/resume.
- [ ] Run tests and confirm behavioral failures.
- [ ] Implement the math and detectors, then implement ARKit joint sampling by composing hand-anchor and joint transforms.
- [ ] Implement synthetic observations through the identical detector inputs; label fallback state in the model.
- [ ] Rerun detector tests and a simulator build; require zero failures.
- [ ] Commit with `feat: add hand movement observation pipeline`.

### Task 4: Implement Balance Platform and Squeeze Buddy

**Files:**
- Create: `RehabPal/Features/Balance/BalanceSession.swift`
- Create: `RehabPal/Features/Balance/BalancePlatformView.swift`
- Create: `RehabPal/Features/Squeeze/SqueezeSession.swift`
- Create: `RehabPal/Features/Squeeze/SqueezeBuddyView.swift`
- Create: `RehabPalTests/ExerciseSessionTests.swift`

**Interfaces:**
- Produces: balanced four-direction schedules, primitive platform scenes, prescribed-dose completion callbacks, and gameplay-only result types.

- [ ] Write failing tests proving equal direction distribution, automatic prescribed-dose completion, no progress during tracking loss, and squeeze completion only after reopening.
- [ ] Implement deterministic session models and run tests green.
- [ ] Build Balance Platform entirely from RealityKit box/sphere/cylinder primitives and constrain the ball to the platform.
- [ ] Build Squeeze Buddy feedback around normalized closure without any force claim.
- [ ] Verify both features complete via synthetic observations and commit with `feat: add prescribed spatial exercises`.

### Task 5: Implement assessment, symptoms, and report separation

**Files:**
- Create: `RehabPal/Features/Assessment/AssessmentSession.swift`
- Create: `RehabPal/Features/Symptoms/SymptomResult.swift`
- Create: `RehabPal/Features/Report/AfterCareReport.swift`
- Create: `RehabPalTests/AssessmentReportTests.swift`

**Interfaces:**
- Produces: fixed-condition `AssessmentResult`, threshold-derived follow-up flag, and report sections for assessment, gameplay, and patient-reported data.

- [ ] Write failing tests for fixed assessment parameters versus forgiving game tolerances, threshold boundaries, low-confidence labeling, and source-category separation.
- [ ] Implement the fixed two-attempt wrist and five-repetition squeeze protocols.
- [ ] Implement symptom evaluation and descriptive report comparison values without diagnosis.
- [ ] Rerun focused and full tests, then commit with `feat: add daily assessment and after-care report`.

### Task 6: Build the complete SwiftUI demo flow

**Files:**
- Modify: `RehabPal/ContentView.swift`
- Modify: `RehabPal/RehabPalApp.swift`
- Create: `RehabPal/Views/HomeView.swift`
- Create: `RehabPal/Views/MedicationGateView.swift`
- Create: `RehabPal/Views/DailyRoutineView.swift`
- Create: `RehabPal/Views/AssessmentView.swift`
- Create: `RehabPal/Views/SymptomCheckView.swift`
- Create: `RehabPal/Views/AfterCareReportView.swift`
- Create: `RehabPal/Views/PetRewardView.swift`
- Create: `RehabPal/Views/DemoSettingsView.swift`

**Interfaces:**
- Consumes: `AppState` eligibility and feature models.
- Produces: Home-first navigation through all ten UX pages with large controls and a labeled fallback toggle.

- [ ] Add view-model tests for visible actions and locked destinations before implementing routing.
- [ ] Implement Home, medication gate, order-independent routine, introductions, exercises, assessment, symptom check, report, and pet reward.
- [ ] Ensure only `AppState` methods advance gates; hide no bypass in demo settings.
- [ ] Add Reset Demo Day and full-for-today messaging.
- [ ] Run the fallback walkthrough in both exercise orders and commit with `feat: build complete RehabPal demo flow`.

### Task 7: Integrate legally redistributable placeholder assets

**Files:**
- Modify: `RealityKitContent/Sources/RealityKitContent/RehabPalAssets.swift`
- Create: `RealityKitContent/Sources/RealityKitContent/Resources/PlaceholderPet.usdz`
- Create: `RealityKitContent/Sources/RealityKitContent/Resources/PlaceholderTreat.usdz`
- Create: `ASSET_ATTRIBUTION.md`
- Create: `RehabPalTests/AssetCatalogTests.swift`

**Interfaces:**
- Produces: replaceable pet/treat lookups with generated primitive fallbacks.

- [ ] Research original asset pages and verify creator, exact license, redistribution permission, source URL, and format before downloading.
- [ ] Convert permitted source formats to USDZ where necessary and record exact commands and access date.
- [ ] Write a failing lookup/fallback test, integrate assets and primitive fallbacks, then run it green.
- [ ] Confirm no Balance Platform model was downloaded and commit with `feat: add attributed placeholder pet assets`.

### Task 8: Verify the complete one-shot demo

**Files:**
- Create: `docs/demo-walkthrough.md`
- Modify: `README.md`

**Interfaces:**
- Produces: repeatable simulator/device walkthrough and verified build artifacts.

- [ ] Run all unit tests and require zero failures.
- [ ] Run a clean generic visionOS Simulator build and require `BUILD SUCCEEDED`.
- [ ] Walk through medication No then Yes, both exercise orders, tracking loss/resume, assessment, symptoms, report, feeding, full-for-today lock, and reset using fallback mode.
- [ ] Document live-device permission and hand-tracking steps separately from fallback disclosure.
- [ ] Verify no backend/network dependencies, no user-state files, complete attribution, and no temporary project names.
- [ ] Commit with `docs: add verified RehabPal demo walkthrough`.
