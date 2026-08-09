# Pet Hunger Design

## Goal

Show the existing normalized RehabPal pet on the home page with a hunger bar that changes according to real elapsed time. Feeding the end-of-routine treat restores slightly more hunger than the pet loses in one day. The feature remains entirely local and requires no backend.

## User experience

- A new installation starts at 50% hunger.
- The home page shows the RealityKit pet above a clearly labeled hunger bar and percentage.
- Hunger decreases continuously by 15 percentage points per elapsed 24 hours, including time while the app is closed.
- Feeding the earned daily treat adds 20 percentage points.
- Hunger is always clamped to the inclusive range 0–100%.
- Completing the routine still awards only one treat per demo day.
- Resetting the demo routine does not reset hunger or its last-updated timestamp.
- Demo Settings includes a “Simulate one day passing” action so the time behavior can be demonstrated consistently without changing the device clock.

The bar represents remaining fullness: a higher value means the pet is less hungry. Copy will make this clear despite the concise “Hunger” label.

## Architecture and data flow

`PetHungerStore` owns hunger persistence and elapsed-time calculations. It stores the last resolved fullness and its timestamp in local preferences through `UserDefaults`, exposed to SwiftUI through the existing observable `AppState`. The calculation accepts an explicit date so tests and the demo-day action remain deterministic.

When hunger is read or the app becomes active, the store resolves elapsed loss, persists the new value and timestamp, and publishes the result. Feeding first resolves elapsed loss at the current time, then applies the 20-point reward. This prevents background time from being skipped. The app does not use timers for correctness; a low-frequency home-page timeline refresh only keeps the visible percentage current while the page remains open.

`HomeView` reuses `RehabPalAssets.loadPet()`, which already normalizes the asset to a safe tabletop size. `PetRewardView` continues to call `AppState.feedPet()`, which additionally feeds the hunger store after the existing reward guards pass.

## Error handling and boundaries

- Missing or malformed persisted values fall back to 50% at the current timestamp.
- Future timestamps cause no hunger loss and are replaced with the current timestamp when resolved.
- Very long elapsed periods clamp at 0%.
- Repeated treat actions remain blocked by the existing `petIsFull` daily guard.
- A missing pet asset continues to use the existing primitive fallback.

## Verification

Unit tests cover the 50% initial value, fractional and multi-day elapsed loss, lower and upper clamping, the 20-point treat increase, time resolution before feeding, persistence, routine reset behavior and the simulated-day action. Existing strict routine-gating tests remain intact. A visionOS simulator build verifies the pet, local media and RealityKit package still bundle correctly.
