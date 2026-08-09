import RealityKitContent
import RealityKit
import XCTest

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
}
