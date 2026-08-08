# Xcode Template Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import the reusable Xcode-generated visionOS assets, USDA resources, and safe build settings from `/Users/event/Documents/temporary_pal` without replacing RehabPal's project, package, tests, volumetric scene, or Git history.

**Architecture:** The existing file-system-synchronized `RehabPal` group discovers imported application resources automatically. The existing app continues to load `RehabPalAssets.makePlaceholderScene()` from the local `RealityKitContent` package; imported USDA files remain application-level placeholders for later scene work.

**Tech Stack:** Xcode 27, Swift 6, SwiftUI, RealityKit, visionOS 2+, XCTest

## Global Constraints

- Treat `/Users/event/Documents/temporary_pal` as read-only.
- Keep project and target name `RehabPal`.
- Keep bundle identifier `com.rehabpal.app`.
- Keep visionOS deployment target 2.0.
- Keep the volumetric `WindowGroup` and nested `UIWindowSceneSessionRoleVolumetricApplication` manifest entry.
- Keep the local `RealityKitContent` package, `RehabPalTests`, and shared `RehabPal` scheme.
- Do not copy `temporary_pal.xcodeproj`, generated Swift app/view files, generated Info.plist, `xcuserdata`, or user-state files.
- Do not change application behavior in this migration.

---

### Task 1: Import Xcode-generated application resources

**Files:**
- Create: `RehabPal/Assets.xcassets/Contents.json`
- Create: `RehabPal/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `RehabPal/Assets.xcassets/AppIcon.solidimagestack/Contents.json`
- Create: `RehabPal/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Contents.json`
- Create: `RehabPal/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/Contents.json`
- Create: `RehabPal/Assets.xcassets/AppIcon.solidimagestack/Middle.solidimagestacklayer/Contents.json`
- Create: `RehabPal/Assets.xcassets/AppIcon.solidimagestack/Middle.solidimagestacklayer/Content.imageset/Contents.json`
- Create: `RehabPal/Assets.xcassets/AppIcon.solidimagestack/Back.solidimagestacklayer/Contents.json`
- Create: `RehabPal/Assets.xcassets/AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/Contents.json`
- Create: `RehabPal/Resources/Scene.usda`
- Create: `RehabPal/Resources/Materials/GridMaterial.usda`

**Interfaces:**
- Consumes: Exact source files under `/Users/event/Documents/temporary_pal/temporary_pal/Assets.xcassets` and `/Users/event/Documents/temporary_pal/temporary_pal/Resources`.
- Produces: An app-level asset catalog and template USDA scene discoverable by the synchronized `RehabPal` group.

- [ ] **Step 1: Verify the resource migration check fails before copying**

Run:

```bash
test -f RehabPal/Assets.xcassets/Contents.json && test -f RehabPal/Resources/Scene.usda
```

Expected: non-zero exit because both destination resources are absent.

- [ ] **Step 2: Reconfirm source integrity before copying**

Run:

```bash
find /Users/event/Documents/temporary_pal/temporary_pal/Assets.xcassets /Users/event/Documents/temporary_pal/temporary_pal/Resources -type f -print -exec shasum -a 256 {} \;
```

Expected: 11 files. `Scene.usda` SHA-256 is `62c55e8d4cfc5d3b696465ee93fc97fde1fd59f05e412f985a1044ecc32d15c7`; `GridMaterial.usda` SHA-256 is `7c8a8886dd5446f294f87fe1cd399f3395fcc6fa245b155a56e649e778b39658`.

- [ ] **Step 3: Copy only the approved resource directories**

Create the destination trees from the approved sources only:

```bash
cp -R /Users/event/Documents/temporary_pal/temporary_pal/Assets.xcassets RehabPal/Assets.xcassets
cp -R /Users/event/Documents/temporary_pal/temporary_pal/Resources RehabPal/Resources
```

Do not read from or copy `temporary_pal.xcodeproj/xcuserdata`.

- [ ] **Step 4: Verify copied file hashes match their sources**

Run:

```bash
diff -r /Users/event/Documents/temporary_pal/temporary_pal/Assets.xcassets RehabPal/Assets.xcassets
diff -r /Users/event/Documents/temporary_pal/temporary_pal/Resources RehabPal/Resources
```

Expected: both commands exit 0 with no output.

### Task 2: Adopt safe Xcode-generated build settings

**Files:**
- Modify: `RehabPal.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Existing app target Debug and Release configurations.
- Produces: Template-aligned compiler, signing, asset-catalog, and runpath settings without changing deployment target, scene role, package linkage, or product identity.

- [ ] **Step 1: Capture the current protected settings**

Run:

```bash
xcodebuild -showBuildSettings -project RehabPal.xcodeproj -scheme RehabPal -configuration Debug | rg 'PRODUCT_BUNDLE_IDENTIFIER|XROS_DEPLOYMENT_TARGET|INFOPLIST_FILE|SWIFT_VERSION'
```

Expected values: `com.rehabpal.app`, `2.0`, `RehabPal/Info.plist`, and `6.0`.

- [ ] **Step 2: Add the approved target settings to Debug and Release**

Set these exact app-target values in both configurations:

```text
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor
DEVELOPMENT_TEAM = JWQW84H342
LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks")
STRING_CATALOG_GENERATE_SYMBOLS = YES
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
```

Set `ENABLE_USER_SCRIPT_SANDBOXING = YES` in both project configurations. Do not change `PRODUCT_BUNDLE_IDENTIFIER`, `XROS_DEPLOYMENT_TARGET`, `INFOPLIST_FILE`, `SWIFT_VERSION`, package references, targets, or schemes.

- [ ] **Step 3: Verify the settings and protected values**

Run:

```bash
xcodebuild -showBuildSettings -project RehabPal.xcodeproj -scheme RehabPal -configuration Debug | rg 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME|DEVELOPMENT_TEAM|LD_RUNPATH_SEARCH_PATHS|PRODUCT_BUNDLE_IDENTIFIER|XROS_DEPLOYMENT_TARGET|INFOPLIST_FILE|SWIFT_VERSION'
```

Expected: imported settings are present and protected values remain `com.rehabpal.app`, `2.0`, `RehabPal/Info.plist`, and `6.0`.

### Task 3: Verify and commit the migration

**Files:**
- Verify: `RehabPal.xcodeproj/project.pbxproj`
- Verify: `RehabPal/Info.plist`
- Verify: `RealityKitContent/Package.swift`
- Verify: `RehabPalTests/RealityKitContentSmokeTests.swift`
- Verify: imported files from Task 1

**Interfaces:**
- Consumes: Imported resources and updated settings.
- Produces: A verified migration commit that leaves the source template unchanged.

- [ ] **Step 1: Confirm project structure and package resolution**

Run:

```bash
xcodebuild -list -project RehabPal.xcodeproj
```

Expected: `RehabPal` and `RehabPalTests` targets, `RehabPal` scheme, and local `RealityKitContent` package.

- [ ] **Step 2: Run the Vision Pro simulator smoke test**

Run:

```bash
xcodebuild test -quiet -project RehabPal.xcodeproj -scheme RehabPal -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -derivedDataPath /tmp/rehabpal-template-migration-test CODE_SIGNING_ALLOWED=NO
```

Expected: exit 0 and one passing test.

- [ ] **Step 3: Run a clean generic visionOS simulator build**

Run:

```bash
xcodebuild build -quiet -project RehabPal.xcodeproj -scheme RehabPal -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/rehabpal-template-migration-build CODE_SIGNING_ALLOWED=NO
```

Expected: exit 0.

- [ ] **Step 4: Verify the built app**

Run:

```bash
plutil -extract UIApplicationSceneManifest.UIApplicationPreferredDefaultSceneSessionRole raw /tmp/rehabpal-template-migration-build/Build/Products/Debug-xrsimulator/RehabPal.app/Info.plist
test -f /tmp/rehabpal-template-migration-build/Build/Products/Debug-xrsimulator/RehabPal.app/Assets.car
test -f /tmp/rehabpal-template-migration-build/Build/Products/Debug-xrsimulator/RehabPal.app/Scene.usda
```

Expected: the role is `UIWindowSceneSessionRoleVolumetricApplication`; the compiled asset catalog and USDA scene are bundled.

- [ ] **Step 5: Confirm repository hygiene**

Run:

```bash
git diff --check
git status --short
git ls-files | rg 'xcuserdata|\.build/|DerivedData|temporary_pal' && exit 1 || exit 0
```

Expected: no whitespace errors and no forbidden generated or temporary-project paths.

- [ ] **Step 6: Commit**

```bash
git add RehabPal.xcodeproj/project.pbxproj RehabPal/Assets.xcassets RehabPal/Resources
git commit -m "chore: migrate Xcode template resources"
```
