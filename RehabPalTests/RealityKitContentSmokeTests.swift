import RealityKitContent
import XCTest

final class RealityKitContentSmokeTests: XCTestCase {
    @MainActor
    func testPlaceholderSceneCanBeLoaded() {
        let scene = RehabPalAssets.makePlaceholderScene()

        XCTAssertEqual(scene.name, "placeholder-pet")
        XCTAssertEqual(scene.children.count, 1)
    }
}
