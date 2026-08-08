# RehabPal Xcode Project Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a minimal, runnable visionOS Xcode project with a local `RealityKitContent` package and smoke-test coverage.

**Architecture:** A SwiftUI visionOS app presents a `RealityView` populated by a public factory in the local RealityKit package. The project contains one app target and one XCTest target, with no backend or third-party dependencies.

**Tech Stack:** Xcode 27, Swift 6, SwiftUI, RealityKit, visionOS 2+

## Global Constraints

- Branch from `main` in an isolated worktree.
- Keep the app minimal and runnable in the visionOS simulator.
- Include a local package named `RealityKitContent`.
- Do not restructure unrelated repository content.
- Treat generated Xcode boilerplate and configuration as the user-approved TDD exception.
- Require a smoke test, `xcodebuild test`, and `xcodebuild build` before integration.

---

### Task 1: Xcode and RealityKit foundation

**Files:**
- Create: `RehabPal.xcodeproj/project.pbxproj`
- Create: `RehabPal.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- Create: `RehabPal.xcodeproj/xcshareddata/xcschemes/RehabPal.xcscheme`
- Create: `RealityKitContent/Package.swift`
- Create: `RealityKitContent/Sources/RealityKitContent/RehabPalAssets.swift`

**Interfaces:**
- Produces: `@MainActor RehabPalAssets.makePlaceholderScene() -> Entity`

- [ ] Create the Xcode project with visionOS app and XCTest targets.
- [ ] Add the local package product to both targets.
- [ ] Add a package scene factory returning a named RealityKit entity.
- [ ] Run `xcodebuild -list -project RehabPal.xcodeproj` and confirm both targets and the shared scheme are discovered.

### Task 2: Minimal runnable app and smoke test

**Files:**
- Create: `RehabPal/RehabPalApp.swift`
- Create: `RehabPal/ContentView.swift`
- Create: `RehabPalTests/RealityKitContentSmokeTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `RehabPalAssets.makePlaceholderScene() -> Entity`

- [ ] Add a SwiftUI app entry point and `RealityView` that loads the package entity.
- [ ] Add an XCTest assertion for the entity's stable placeholder name.
- [ ] Document how to open and run the visionOS project.
- [ ] Run the XCTest target in the visionOS simulator and require zero failures.
- [ ] Build the app for the generic visionOS simulator destination and require exit code 0.
- [ ] Commit the verified scaffold.

