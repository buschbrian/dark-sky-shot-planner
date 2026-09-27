import XCTest

/// M12 capture lifetime on a physical iPhone (the simulator has no camera):
/// leave during the countdown, acquisition and stacking, background the app
/// mid-run, and check each time that one run exists, the camera and idle
/// timer are released, and the frames are offered again. Needs camera
/// permission already granted. Reads the Debug-only `capture.debug` line.
final class CaptureLifecycleTests: XCTestCase {
    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Capture needs a physical camera")
        #endif
        continueAfterFailure = false
    }

    @MainActor
    private func debugState(_ app: XCUIApplication) -> String {
        app.staticTexts["capture.debug"].label
    }

    @MainActor
    private func waitFor(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 30) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if app.staticTexts["capture.debug"].exists, debugState(app).contains(text) { return true }
            usleep(200_000)
        }
        return false
    }

    @MainActor
    private func status(_ app: XCUIApplication, contains text: String, timeout: TimeInterval) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func openCapture(_ app: XCUIApplication) {
        if !app.buttons["tools.capture"].exists { app.tabBars.buttons["Tools"].tap() }
        let row = app.buttons["tools.capture"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["capture.debug"].waitForExistence(timeout: 20))
        XCTAssertTrue(waitFor(app, "run:none"), "no run left over: \(debugState(app))")
        XCTAssertTrue(waitFor(app, "camera:on"), "camera opens on the screen: \(debugState(app))")
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["tools.capture"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testLeavingAndBackgroundingEndTheRunCleanly() {
        let app = XCUIApplication()
        app.launchArguments = ["-DarkSkyUITest"]
        app.launch()

        // 1. Leave during the countdown.
        openCapture(app)
        app.buttons["10 s"].tap()
        app.buttons["capture.start"].tap()
        XCTAssertTrue(status(app, contains: "Self-timer", timeout: 10))
        XCTAssertTrue(debugState(app).contains("idle:disabled"), debugState(app))
        back(app)
        openCapture(app)
        XCTAssertTrue(waitFor(app, "idle:enabled"), debugState(app))
        snapshot("1-after-countdown-leave")

        // 2. Leave during acquisition; the frames shot are offered on return.
        app.buttons["No timer"].tap()
        app.buttons["capture.start"].tap()
        XCTAssertTrue(status(app, contains: "Frame 3 of", timeout: 60))
        back(app)
        openCapture(app)
        XCTAssertTrue(waitFor(app, "idle:enabled"), debugState(app))
        let stackSaved = app.buttons["capture.stackSaved"]
        XCTAssertTrue(stackSaved.waitForExistence(timeout: 10), "unstacked frames offered")
        snapshot("2-after-acquisition-leave")

        // 3. Leave during stacking; the same frames are still offered.
        stackSaved.tap()
        XCTAssertTrue(app.buttons["capture.stopStacking"].waitForExistence(timeout: 10))
        back(app)
        openCapture(app)
        XCTAssertTrue(app.buttons["capture.stackSaved"].waitForExistence(timeout: 10), "frames kept after a cancelled stack")
        snapshot("3-after-stacking-leave")

        // 4. Background mid-run, then return to the same screen.
        app.buttons["capture.start"].tap()
        XCTAssertTrue(status(app, contains: "Frame 2 of", timeout: 60))
        XCUIDevice.shared.press(.home)
        sleep(4)
        app.activate()
        XCTAssertTrue(status(app, contains: "not stacked", timeout: 30), "background ends the run with frames kept")
        XCTAssertTrue(waitFor(app, "run:none"), debugState(app))
        XCTAssertTrue(waitFor(app, "idle:enabled"), debugState(app))
        XCTAssertTrue(waitFor(app, "camera:on"), "camera back on for the visible screen: \(debugState(app))")
        snapshot("4-after-background")

        // 5. Stop and stack completes a stack.
        app.buttons["capture.start"].tap()
        XCTAssertTrue(status(app, contains: "Frame 3 of", timeout: 60))
        app.buttons["capture.stopAndStack"].tap()
        XCTAssertTrue(status(app, contains: "stacked", timeout: 180))
        XCTAssertTrue(waitFor(app, "run:none"), debugState(app))
        snapshot("5-stop-and-stack")
        back(app)
    }
}
