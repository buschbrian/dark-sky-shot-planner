import XCTest

/// Tonight (M2 + M4). `-DarkSkyUITest` starts with no remembered place, no
/// network and an empty conditions cache, so every run is the airplane-mode case.
final class TonightTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-DarkSkyUITest"]
        app.launch()
    }

    @MainActor
    private func enterLocation(_ text: String) {
        let choose = app.buttons["tonight.chooseLocation"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()
        let field = app.textFields["location.input"].exists ? app.textFields["location.input"] : app.textViews["location.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["location.use"].tap()
        XCTAssertTrue(app.otherElements["tonight.headline"].waitForExistence(timeout: 10)
            || app.staticTexts["tonight.headline"].waitForExistence(timeout: 1))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    func testTypingCoordinatesAndSwitchingNights() {
        enterLocation("38.35, -109.95")
        XCTAssertTrue(element("tonight.place").label.contains("38.3500, -109.9500"))

        let date = element("tonight.date")
        XCTAssertTrue(date.label.hasSuffix("tonight"), date.label)
        let tonightLabel = date.label
        let headline = element("tonight.headline").label

        element("tonight.nextNight").tap()
        XCTAssertTrue(date.label.hasSuffix("tomorrow night"), date.label)
        XCTAssertNotEqual(date.label, tonightLabel)

        element("tonight.previousNight").tap()
        element("tonight.previousNight").tap()
        XCTAssertTrue(date.label.hasSuffix("last night"), date.label)

        element("tonight.backToTonight").tap()
        XCTAssertEqual(date.label, tonightLabel)
        XCTAssertEqual(element("tonight.headline").label, headline, "same night, same answer")
    }

    @MainActor
    func testWebShareLinkOpensThePlaceAndNight() {
        enterLocation("https://example.github.io/dark-sky-shot-planner/#lat=38.53&lon=-109.9&date=2026-10-10")
        XCTAssertTrue(element("tonight.place").label.contains("38.5300, -109.9000"))
        let date = element("tonight.date").label
        XCTAssertTrue(date.contains("October") && date.contains("10"), date)
        XCTAssertTrue(element("tonight.headline").label.contains("minutes of moon-free darkness"))
    }

    @MainActor
    func testBadInputIsRejectedWithAReason() {
        let choose = app.buttons["tonight.chooseLocation"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()
        let field = element("location.input")
        field.tap()
        field.typeText("95, 200")
        app.buttons["location.use"].tap()
        XCTAssertTrue(element("location.problem").waitForExistence(timeout: 3))
    }

    /// VoiceOver reads top to bottom: the headline answer, the verdict, then the details.
    @MainActor
    func testVoiceOverReadsTheAnswerInOrder() {
        enterLocation("38.35, -109.95")
        let ids = ["tonight.place", "tonight.date", "tonight.headline", "tonight.verdict",
                   "tonight.darkness", "tonight.moon", "tonight.gc"]
        let frames = ids.map { id -> CGRect in
            let e = element(id)
            XCTAssertTrue(e.waitForExistence(timeout: 5), id)
            return e.frame
        }
        for (a, b) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThan(a.minY, b.minY)
        }
        let headline = element("tonight.headline").label
        XCTAssertTrue(headline.first?.isNumber == true && headline.contains("minutes of moon-free darkness"), headline)
        XCTAssertTrue(element("tonight.verdict").label.contains("Source"), "the verdict names its source")
    }

    /// Airplane mode with an empty cache: the astronomy still answers, and
    /// conditions read "unavailable", never zero or good.
    @MainActor
    func testOfflineConditionsAreUnavailableNeverGood() {
        enterLocation("38.35, -109.95")
        let origin = element("tonight.conditionsOrigin")
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        let offline = NSPredicate(format: "label CONTAINS 'nothing cached'")
        expectation(for: offline, evaluatedWith: origin)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(element("tonight.verdict").label.hasPrefix("Go"), "missing data never reads as good")

        element("tonight.factors").tap()
        let cloud = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Cloud cover (mean over window)'")).firstMatch
        XCTAssertTrue(cloud.waitForExistence(timeout: 5))
        XCTAssertTrue(cloud.label.contains("unavailable"), cloud.label)
        XCTAssertFalse(cloud.label.contains("0%"), cloud.label)
        element("factors.done").tap()
    }

    /// Screens for the visual field-mode check, kept as test attachments.
    @MainActor
    func testScreenshotTour() {
        enterLocation("https://example.github.io/#lat=38.35&lon=-109.95&date=2026-10-10")
        for field in [false, true] {
            if field { app.buttons["Field mode"].firstMatch.tap() }
            let mode = field ? "field" : "normal"
            snap("\(mode)-1-top")
            app.swipeUp()
            snap("\(mode)-2-middle")
            app.swipeUp()
            snap("\(mode)-3-bottom")
            app.swipeDown()
            app.swipeDown()
            element("tonight.factors").tap()
            snap("\(mode)-4-factors")
            element("factors.done").tap()
            element("tonight.date").tap()
            snap("\(mode)-5-calendar")
            app.buttons["Cancel"].firstMatch.tap()
            element("tonight.location").tap()
            snap("\(mode)-6-location")
            if !field {
                element("location.input").tap()
                snap("\(mode)-7-keyboard")
            }
            element("location.cancel").tap()
        }
    }

    @MainActor
    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Opt-in, needs the network (and optionally a local Worker):
    /// `TEST_RUNNER_TONIGHT_LIVE=1 xcodebuild test ...`.
    @MainActor
    func testLiveConditionsTour() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONIGHT_LIVE"] != nil, "live network test")
        app.terminate()
        app.launchArguments = ["-DarkSkyUITestLive"]
        app.launch()
        enterLocation("38.35, -109.95")
        let origin = element("tonight.conditionsOrigin")
        let loaded = NSPredicate(format: "label CONTAINS 'Worker' OR label CONTAINS 'Open-Meteo'")
        expectation(for: loaded, evaluatedWith: origin)
        waitForExpectations(timeout: 60)
        for field in [false, true] {
            if field { app.buttons["Field mode"].firstMatch.tap() }
            let mode = field ? "live-field" : "live-normal"
            snap("\(mode)-1-top")
            app.swipeUp()
            snap("\(mode)-2-middle")
            app.swipeUp()
            snap("\(mode)-3-bottom")
            app.swipeDown()
            app.swipeDown()
            element("tonight.factors").tap()
            snap("\(mode)-4-factors")
            app.swipeUp()
            snap("\(mode)-5-factors-more")
            element("factors.done").tap()
        }
    }
}
