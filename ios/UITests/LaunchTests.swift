import XCTest

/// UI automation still requires XCTest; swift-testing has no XCUIApplication.
final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchesToTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-FieldMode", "NO"]
        app.launch()
        for tab in ["Tonight", "Map", "Sky", "Spots", "Tools"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 10), "missing tab \(tab)")
        }
        XCTAssertTrue(app.segmentedControls.buttons["Week"].exists, "Week lives inside the Tonight tab")
    }
}
