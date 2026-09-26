import XCTest

/// The Simulator has no camera or motion sensors, so the Sky tab always
/// shows its labelled simulated view here: facing south, 20° up.
final class SkyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openSky(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        app.tabBars.buttons["Sky"].tap()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func summary(_ app: XCUIApplication) -> String {
        let overlay = element(app, "sky.overlay")
        XCTAssertTrue(overlay.waitForExistence(timeout: 15), "overlay summary missing")
        return overlay.value as? String ?? ""
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 23:00 MDT on 14 July 2026 at Candlestick Camp: the GC is near the
    /// meridian, about 22° up, so it sits in the simulated view.
    @MainActor
    func testSimulatedViewListsTargetsForVoiceOver() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z"])
        let text = summary(app)
        XCTAssertTrue(text.contains("Facing south"), text)
        XCTAssertTrue(text.contains("On screen: Galactic Center"), text)
        XCTAssertTrue(text.contains("Milky Way band on screen"), text)
        XCTAssertTrue(text.contains("Terrain horizon shown"), text)
        XCTAssertFalse(text.contains("approximate"), text)
        XCTAssertTrue(element(app, "sky.simulated").exists, "the simulated view must say so")
        XCTAssertTrue(element(app, "sky.scrubber").exists)
        attachScreenshot("sky-normal")

        element(app, "sky.fieldMode").tap()
        XCTAssertTrue(element(app, "sky.overlay").waitForExistence(timeout: 5))
        attachScreenshot("sky-field")
    }

    /// Full Moon in the east-southeast on 26 September 2026, 22:00 MDT.
    @MainActor
    func testPoorCompassLooksApproximateUntilCalibrated() {
        let app = openSky(["-SkyDemoTime", "2026-09-27T04:00:00Z", "-SkyDemoHeadingAccuracy", "25"])
        XCTAssertTrue(summary(app).contains("Positions approximate, compass accuracy ±25°"))
        XCTAssertTrue(element(app, "sky.approximate").exists)
        attachScreenshot("sky-approximate")

        element(app, "sky.calibrate").tap()
        app.buttons["Moon"].firstMatch.tap()
        element(app, "sky.calibration.align").tap()

        let heading = element(app, "sky.heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.label.contains("calibrated on Moon"), heading.label)
        XCTAssertFalse(summary(app).contains("approximate"))
        XCTAssertFalse(element(app, "sky.approximate").exists)
        attachScreenshot("sky-calibrated")
    }

    @MainActor
    func testInvalidHeadingStaysApproximateEvenWhenCalibrated() {
        let app = openSky(["-SkyDemoTime", "2026-09-27T04:00:00Z", "-SkyDemoHeadingAccuracy", "invalid"])
        XCTAssertTrue(summary(app).contains("no valid compass heading"))
        element(app, "sky.calibrate").tap()
        app.buttons["Moon"].firstMatch.tap()
        element(app, "sky.calibration.align").tap()
        XCTAssertTrue(element(app, "sky.heading").label.contains("calibrated on Moon"))
        XCTAssertTrue(summary(app).contains("no valid compass heading"))
    }

    /// The simulated phone sweeps around the south at display rate, through
    /// the same TimelineView + Canvas path as the real sensors. Reports the
    /// meter rather than asserting on it: Simulator timing is the Mac's.
    @MainActor
    func testSweepingFrameTimes() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z", "-SkyDemoSweep", "YES", "-SkyFrameStats", "YES"])
        let stats = element(app, "sky.frameStats")
        XCTAssertTrue(stats.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 12)
        let text = stats.label
        print("SKY FRAME STATS: \(text)")
        let note = XCTAttachment(string: text)
        note.name = "sky-frame-stats"
        note.lifetime = .keepAlways
        add(note)
        attachScreenshot("sky-sweep")
        XCTAssertTrue(text.contains("interval p50"), text)
    }
}
