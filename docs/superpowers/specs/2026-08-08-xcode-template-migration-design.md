# Xcode Template Migration Design

## Goal

Migrate the useful Xcode-generated files from `/Users/event/Documents/temporary_pal` into RehabPal while preserving the existing product name, Git history, volumetric scene, `RealityKitContent` package, tests, and approved demo specification.

## Approach

Use a selective migration rather than replacing the entire project. The generated temporary project does not contain the existing local package or test target, and its standard window scene would undo RehabPal's volumetric configuration.

## Files to Import

Copy the generated application resources into equivalent RehabPal paths:

- `temporary_pal/Assets.xcassets` -> `RehabPal/Assets.xcassets`
- `temporary_pal/Resources/Scene.usda` -> `RehabPal/Resources/Scene.usda`
- `temporary_pal/Resources/Materials/GridMaterial.usda` -> `RehabPal/Resources/Materials/GridMaterial.usda`

Do not copy:

- `temporary_pal.xcodeproj`
- `temporary_palApp.swift`
- `temporary_pal/ContentView.swift`
- `temporary_pal/Info.plist`
- Any `xcuserdata` or user-state files

## Project Settings

Retain:

- Project and target name `RehabPal`
- Product name `RehabPal`
- Bundle identifier `com.rehabpal.app`
- visionOS deployment target 2.0
- Volumetric `WindowGroup`
- Nested `UIWindowSceneSessionRoleVolumetricApplication` manifest entry
- Local `RealityKitContent` package dependency
- `RehabPalTests` target and shared scheme

Adopt useful generated-template settings where they do not change behavior:

- Asset catalog app icon name `AppIcon`
- Asset catalog global accent color name `AccentColor`
- Automatic signing with development team `JWQW84H342`
- App framework runpath `@executable_path/Frameworks`
- User script sandboxing
- Swift approachable concurrency
- Main actor default isolation
- Upcoming member-import visibility
- String catalog symbol generation

Keep Swift language mode 6.0 because the current project and package already compile in that mode. Do not copy the temporary project's Swift 5.0 setting or visionOS 27.0 deployment floor.

## Resource Integration

The file-system-synchronized `RehabPal` group will discover the imported asset catalog and resources automatically. Preserve the existing synchronized exception that prevents `Info.plist` from being copied as a bundle resource.

The generated USDA files are template placeholders. They remain separate from the `RealityKitContent` package and can support application-level scene experiments. Future pet, treat, and bed assets still belong in `RealityKitContent` with licensing recorded in `ASSET_ATTRIBUTION.md`.

The app continues to render `RehabPalAssets.makePlaceholderScene()` from the local package. This migration does not change application behavior or switch `ContentView` to the generated `Scene.usda`.

## Safety and Failure Handling

- Treat `/Users/event/Documents/temporary_pal` as read-only.
- Do not migrate personal Xcode user data.
- Do not delete or restructure product specifications, plans, tests, or package content.
- If any imported asset catalog or USDA file fails compilation, compare it against the unchanged source and remove only the incompatible imported file.
- Keep all migration changes confined to the active `one-shot-prototype` branch.

## Verification

- Confirm the source template remains unchanged.
- Confirm the Xcode project lists the `RehabPal` and `RehabPalTests` targets and resolves `RealityKitContent` locally.
- Confirm the built Info.plist retains the volumetric scene role.
- Run `xcodebuild test` on the Apple Vision Pro simulator and require zero failures.
- Run a clean generic visionOS simulator build and require exit code 0.
- Confirm imported assets appear in the built app bundle.
- Confirm no `xcuserdata`, `.build`, `DerivedData`, or temporary-project files are tracked.

