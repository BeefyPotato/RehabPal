import RealityKitContent
import RealityKit
import simd
import XCTest
@testable import RehabPal

final class AssetCatalogTests: XCTestCase {
    @MainActor
    func testLicensedPlaceholderAssetsLoadFromPackage() async {
        let pet = await RehabPalAssets.loadPet()
        let treat = await RehabPalAssets.loadTreat()

        XCTAssertEqual(pet.name, "placeholder-pet-asset")
        XCTAssertEqual(treat.name, "placeholder-treat-asset")
        XCTAssertFalse(pet.children.isEmpty)
        XCTAssertFalse(treat.children.isEmpty)
    }

    @MainActor
    func testMissingPlaceholderAssetsReturnNamedPrimitiveFallbacks() async {
        let pet = await RehabPalAssets.loadPet(named: "does-not-exist")
        let treat = await RehabPalAssets.loadTreat(named: "does-not-exist")

        XCTAssertEqual(pet.name, "primitive-pet-fallback")
        XCTAssertEqual(treat.name, "primitive-treat-fallback")
        XCTAssertFalse(pet.children.isEmpty)
        XCTAssertFalse(treat.children.isEmpty)
    }

    @MainActor
    func testPetIsNormalizedToTabletopScaleWithFeetOnGround() async {
        let pet = await RehabPalAssets.loadPet()
        let bounds = pet.visualBounds(relativeTo: nil)
        XCTAssertLessThanOrEqual(max(bounds.extents.x, bounds.extents.y, bounds.extents.z), 0.221)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 0.002)
    }

    func testOriginalInstructionClipsAreBundled() {
        for name in ["balance", "squeeze", "wristAssessment", "fingerROM"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "mp4"), "Missing \(name).mp4")
        }
    }

    func testARKitPrivacyDescriptionsAreBundled() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSHandsTrackingUsageDescription"))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSWorldSensingUsageDescription"))
    }

    func testCC0SheepAssetAndProvenanceAreBundled() throws {
        let sheepURL = try XCTUnwrap(
            Bundle.main.url(forResource: "Sheep", withExtension: "usdz"),
            "Missing Sheep.usdz from the application bundle"
        )
        let attributionURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "LICENSE-AND-ATTRIBUTION",
                withExtension: "txt"
            ),
            "Missing LICENSE-AND-ATTRIBUTION.txt from the application bundle"
        )

        XCTAssertFalse(try Data(contentsOf: sheepURL).isEmpty)
        let attribution = try String(contentsOf: attributionURL, encoding: .utf8)
        XCTAssertTrue(attribution.contains("https://poly.pizza/m/rgJXF570ZK"))
        XCTAssertTrue(attribution.contains("CC0 1.0"))
    }

    @MainActor
    func testCC0SheepUSDZCanLoadFromApplicationBundle() async throws {
        let sheep = try await Entity(named: "Sheep", in: .main)
        XCTAssertFalse(sheep.children.isEmpty)
    }

    @MainActor
    func testSheepDropVisibleModelSelectsAndFitsOnlySheepHierarchy() async throws {
        let importedScene = try await Entity(named: "Sheep", in: .main)

        XCTAssertNotNil(importedScene.findEntity(named: "RootNode"))
        XCTAssertNotNil(importedScene.findEntity(named: "Cube"))
        XCTAssertNotNil(importedScene.findEntity(named: "Camera"))
        XCTAssertNotNil(importedScene.findEntity(named: "Light"))
        XCTAssertNotNil(importedScene.findEntity(named: "env_light"))

        let visibleSheep = try XCTUnwrap(
            SheepDropAsset.makeVisibleModel(from: importedScene)
        )

        XCTAssertEqual(visibleSheep.name, "SheepVisible")
        XCTAssertNotNil(visibleSheep.findEntity(named: "RootNode"))
        XCTAssertNotNil(visibleSheep.findEntity(named: "AnimalArmature"))
        XCTAssertNotNil(visibleSheep.findEntity(named: "Sheep"))
        XCTAssertNil(visibleSheep.findEntity(named: "Cube"))
        XCTAssertNil(visibleSheep.findEntity(named: "Camera"))
        XCTAssertNil(visibleSheep.findEntity(named: "Light"))
        XCTAssertNil(visibleSheep.findEntity(named: "env_light"))

        let bounds = visibleSheep.visualBounds(relativeTo: visibleSheep)
        XCTAssertEqual(bounds.center.x, 0, accuracy: 0.000_1)
        XCTAssertEqual(bounds.center.y, 0, accuracy: 0.000_1)
        XCTAssertEqual(bounds.center.z, 0, accuracy: 0.000_1)
        XCTAssertLessThanOrEqual(
            simd_length(bounds.extents) / 2,
            SheepDropSceneConfiguration.sheepCollisionRadius + 0.000_1
        )
    }
}
