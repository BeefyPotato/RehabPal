import RealityKitContent
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
}
