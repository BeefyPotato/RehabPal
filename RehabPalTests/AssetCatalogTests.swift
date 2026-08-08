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
}
