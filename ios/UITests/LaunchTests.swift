import XCTest

/// UI automation still requires XCTest; swift-testing has no XCUIApplication.
final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchesToPlaceholder() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["placeholder.summary"].waitForExistence(timeout: 10))
    }
}
