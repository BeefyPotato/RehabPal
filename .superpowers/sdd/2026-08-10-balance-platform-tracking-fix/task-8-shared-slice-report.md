# Task 8 Shared Recovery Slice Report

## Completed

- Added `ImmersiveRecoveryPresentation` with exact brief/long titles, preserved progress, five experience-specific instructions, recalibration visibility/readiness, and an explicit normal-instruction replacement contract.
- Added the compact `ImmersiveRecoveryPanel` UI with Recalibrate and Back to Routine actions.
- Added a coordinator-owned Back intent generation so an immersive action can notify the window owner without directly owning window/immersive lifecycle state.
- Added one ContentView return-to-routine path that clears exercise selection, clears AppState authorization, cancels the coordinator, closes/dismisses the immersive lifecycle, and returns diagnostics to Today's Routine.
- Removed the window-level tracking-loss `SessionLifecycleCard`; startup and failure cards remain.
- Existing introduction Back behavior remains connected to exercise selection cancellation.

## Tests and Verification

- Mutation-named RED tests failed for the missing recovery presentation and return-to-routine APIs before implementation.
- Generic visionOS `build-for-testing`: exit 0.
- Generic visionOS app `build`: exit 0.
- `git diff --check`: exit 0.
- Simulator runtime was not claimed or attempted for this timeboxed slice.

## Remaining Task 8 Wiring

- Place the shared panel above each Balance, Squeeze, Sheep, wrist-diagnostic, and finger-diagnostic HUD attachment.
- Pass each panel's Back action to `coordinator.requestReturnToRoutine()` and Recalibrate action to `coordinator.confirmRecalibration()`.
- Hide each normal phase instruction while its recovery presentation is active, while retaining the assisted-progress action in live and Demo sessions.
- Add per-HUD presentation tests proving non-overlap/replacement and action availability.
- Perform physical Vision Pro acceptance of safe dismissal and panel placement.
