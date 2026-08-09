# Joint-Tracked Rehab Games — Final Fix Report

Date: 2026-08-09

Branch: `feature/game-enhancements`

Review range: `535c7d2..754df2e`

Status: **DONE_WITH_CONCERNS**

The complete Critical and Important final-review set is addressed. The branch compiles as an app and as a full test bundle for generic visionOS. Runtime XCTest execution and physical acceptance remain environmental concerns because this Mac has no concrete visionOS simulator or available Vision Pro test destination.

## Inputs reviewed

- `docs/superpowers/specs/2026-08-09-joint-tracked-rehab-games-design.md`
- `docs/superpowers/plans/2026-08-09-joint-tracked-rehab-games.md`
- `.superpowers/sdd/2026-08-09-joint-tracked-rehab-games/review-535c7d2..754df2e.diff` (entire 8,138-line package)
- Current implementation and test sources at `754df2e`

## Fixes completed

### 1. Immersive-open and live-start ordering

- Added `RehabSessionLaunchSequence`, which reserves a coordinator start generation, awaits the mixed immersive open result, and invokes live tracking only after `ImmersiveSessionLifecycle` accepts `.opened`.
- Removed the production `startLive` and `retryLive` convenience bypasses. Production live startup now has one call path: `ContentView` → launch sequence → accepted immersive lifecycle → prepared coordinator start → engine start.
- Added attempt ownership to `ImmersiveSessionLifecycle`. A stale open can dismiss only when no newer owner exists; it cannot close or dismiss a newer launch.
- Added cancellation and final-failure cleanup for delayed open, stale open, failed live startup, provider failure, authorization denial, AppState authorization rejection, and normal cancellation.
- Demo Mode is generation-safe and is activated before its open boundary so immersive processors are constructed with simulated provenance. It still performs no ARKit startup.

### 2. Independent hand tracking frames

- Added the pure `HandJointFrameDemultiplexer` with independent left/right slots.
- `HandTrackingEngine` now processes ARKit anchor `added`, `updated`, and `removed` events.
- Removing or invalidating one hand clears only that hand. An unaffected-hand update or removal cannot erase the prescribed hand.
- `jointFrame(for:)` exposes the requested chirality to the coordinator.
- App-owned frames preserve `AnchorUpdate.timestamp` instead of substituting render/system time. This supports downstream freshness checks as intended by Apple’s [`AnchorUpdate.timestamp`](https://developer.apple.com/documentation/arkit/anchorupdate/timestamp) API.
- The ARKit-to-app mapper remains colocated in `JointFrame.swift`; separating it into another file is the explicitly deferred minor.

### 3. Loss semantics and recalibration acknowledgement

- The coordinator rejects frames that are stale, wrong-hand, or missing any required tracked joint.
- A provider-interruption watermark prevents a cached pre-interruption frame from immediately resuming the session; a genuinely newer frame can resume it.
- ARKit authorization denial and provider-stop events become recoverable session failures. Provider pauses become tracking loss. These are sourced from [`ARKitSession.Event`](https://developer.apple.com/documentation/arkit/arkitsession/event) and [`DataProviderState`](https://developer.apple.com/documentation/arkit/dataproviderstate).
- The common two-second tracking-loss rule applies to balance, squeeze, wrist assessment, and finger assessment. Completed work is preserved and partial work is discarded.
- Long loss publishes a reset generation that remains pending until the active immersive processor actually resets and acknowledges it.
- Balance, squeeze, wrist, and finger views reset their real processor state, recalibrate it from valid required-joint frames, and acknowledge calibration for that generation.
- User confirmation remains disabled until reset acknowledgement, processor calibration acknowledgement, and a currently valid required-joint frame are all present.

### 4. Generation-safe asynchronous startup

- Coordinator prepared-start tokens prevent a cancelled or superseded completion from publishing an old request or stopping a newer session.
- `HandTrackingEngine` has independent startup and active generations. Late success, late failure, and task cancellation cannot mutate the running/error state of a newer generation.
- Engine cancellation still cleans up its own underlying session when its asynchronous run boundary returns.
- Direct unsupported-engine startup again fails before invoking the session boundary.

### 5. Report availability

- Wrist comparison and today’s wrist trend point are gated by wrist tracking confidence.
- Finger rows and today’s finger trend point are gated per digit using `DigitROMSummary.isAvailable`.
- Closure consistency uses only available digit summaries and is unavailable when no digit is available.
- Mixed-confidence results no longer let a strong wrist expose weak fingers or weak fingers hide a strong wrist.
- Charts omit an unavailable today point and explicitly label that state.

### 6. Diagnostic prescription safety

- Central request validation now requires diagnostic goals to be divisible across five subjects and provide at least two attempts per subject.
- One-attempt wrist or hand diagnostic prescriptions therefore fail before startup and cannot produce structurally unavailable summaries.

### 7. Easy correctness minors

- Diagnostic observations are bounded to 256 entries while preserving publication order.
- Repeated identical render-cadence progress and pause states no longer republish the phase.
- The existing untracked `docs/superpowers/plans/2026-08-09-pet-hunger.md` was preserved and excluded from this work.

## TDD and regression coverage

Tests were added before the corresponding production implementations for:

- asynchronous immersive-open/start ordering and cleanup;
- stale lifecycle ownership;
- coordinator and engine A→B startup races;
- engine cancellation and unsupported startup;
- left/right interleaving, removal, and update timestamps;
- stale frames, required-joint confidence, provider/auth events, and interruption caching;
- reset-generation acknowledgement and calibrated confirmation;
- bounded diagnostic queues and deduplicated phase writes;
- diagnostic minimum attempts;
- mixed report confidence and unavailable today points;
- demo provenance during the immersive open boundary.

Initial RED build:

```sh
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/RehabSessionLaunchTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -only-testing:RehabPalTests/HandTrackingEngineTests \
  -only-testing:RehabPalTests/JointFrameTests \
  -only-testing:RehabPalTests/AssessmentReportTests \
  -derivedDataPath /private/tmp/RehabPalFinalFixRed CODE_SIGNING_ALLOWED=NO
```

Result: exit 65 at the expected missing production APIs (`LiveHandJointSessionEvent`, `RehabImmersiveOpenResult`, and related launch/demultiplexing/reset surfaces).

Final focused GREEN build:

```sh
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -only-testing:RehabPalTests/RehabSessionLaunchTests \
  -only-testing:RehabPalTests/RehabSessionCoordinatorTests \
  -only-testing:RehabPalTests/HandTrackingEngineTests \
  -only-testing:RehabPalTests/ImmersiveSessionLifecycleTests \
  -derivedDataPath /private/tmp/RehabPalFinalFixFocusedGreen4 CODE_SIGNING_ALLOWED=NO
```

Result: exit 0.

## Final verification

Full test-bundle compile:

```sh
xcodebuild build-for-testing -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalFinalFixFullFinal CODE_SIGNING_ALLOWED=NO
```

Result: exit 0.

App compile:

```sh
xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalFinalFixAppFinal CODE_SIGNING_ALLOWED=NO
```

Result: exit 0.

Whitespace validation:

```sh
git diff --check
```

Result: exit 0 before report creation; it is rerun as the final pre-commit gate.

Runtime test attempt:

```sh
xcodebuild test-without-building -quiet -project RehabPal.xcodeproj -scheme RehabPal \
  -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/RehabPalFinalFixFull CODE_SIGNING_ALLOWED=NO
```

Result: exit 70 because Xcode requires a concrete device for test execution. `-showdestinations` lists only generic visionOS device/simulator placeholders, so the test bundle could be compiled but not executed here.

## Remaining concerns

1. Run the XCTest bundle on a concrete visionOS simulator or unlocked Vision Pro. This environment has neither.
2. Perform the design-required physical Vision Pro acceptance pass for hand alignment, tray physics, squeeze-face placement, interruption/recovery, and comfort.
3. The pre-existing `InstructionMediaCard.swift` visionOS 27 deprecation warning (`AVPlayerItemDidPlayToEndTime`) remains outside this review scope.
4. ARKit mapper file separation remains the approved deferred minor; the mapper itself is covered by the app-owned demultiplexer boundary and compiles successfully.
