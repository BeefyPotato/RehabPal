# Placeholder Asset Attribution

These models are prototype placeholders and are intentionally isolated behind `RehabPalAssets` so they can be replaced without changing session logic.

## Recovery Pet — Cube Pets dog

- Purpose: Cute placeholder Recovery Pet.
- Original source: https://kenney.nl/assets/cube-pets
- Creator: Kenney (`www.kenney.nl`).
- License: Creative Commons Zero v1.0 Universal (CC0 1.0), https://creativecommons.org/publicdomain/zero/1.0/
- Required attribution: None required. Kenney optionally invites credit to `Kenney` or `www.kenney.nl`.
- Downloaded source format: GLB (`animal-dog.glb`) from Cube Pets 2.0.
- Conversion: `usdextract animal-dog.glb -o <directory>` produced `animal-dog.usdc` and its texture; `usdzip PlaceholderPet.usdz animal-dog.usdc Textures/colormap.png` packaged a RealityKit-compatible USDZ.
- Local path: `RealityKitContent/Sources/RealityKitContent/Resources/PlaceholderPet.usdz`
- Preserved license: `RealityKitContent/Sources/RealityKitContent/Resources/Kenney-Cube-Pets-License.txt`
- Date accessed: 2026-08-08.

## Pet Treat — Food Kit cookie

- Purpose: Simple placeholder food/treat reward.
- Original source: https://kenney.nl/assets/food-kit
- Creator: Kenney (`www.kenney.nl`).
- License: Creative Commons Zero v1.0 Universal (CC0 1.0), https://creativecommons.org/publicdomain/zero/1.0/
- Required attribution: None required. Kenney optionally invites credit to `Kenney` or `www.kenney.nl`.
- Downloaded source format: GLB (`cookie.glb`) from Food Kit 2.0.
- Conversion: `usdextract cookie.glb -o <directory>` produced `cookie.usdc` and its texture; `usdzip PlaceholderTreat.usdz cookie.usdc Textures/colormap.png` packaged a RealityKit-compatible USDZ.
- Local path: `RealityKitContent/Sources/RealityKitContent/Resources/PlaceholderTreat.usdz`
- Preserved license: `RealityKitContent/Sources/RealityKitContent/Resources/Kenney-Food-Kit-License.txt`
- Date accessed: 2026-08-08.

No downloaded models are used for Balance Platform; its platform, ball, and target are generated from RealityKit primitives.
