import XCTest

/// Map tab (M6). The place is set by typing coordinates, never by touching
/// the map (invariant 5).
final class MapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openMap() -> XCUIApplication {
        let app = XCUIApplication()
        // -DarkSkyUITest: no remembered place from an earlier launch (review P2 #2).
        app.launchArguments = ["-DarkSkyUITest", "-resetMapState", "-FieldMode", "NO"]
        app.launch()
        app.tabBars.buttons["Map"].tap()
        return app
    }

    @MainActor
    private func setPlace(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["map.coordinateField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not appear")
        field.typeText(text)
        app.buttons["map.setPlace"].tap()
    }

    @MainActor
    func testMapLoadsAndCoordinateSetsPlaceWithoutTheMap() {
        let app = openMap()
        let map = app.otherElements["map.view"]
        XCTAssertTrue(map.waitForExistence(timeout: 15), "map view missing")
        let timingElement = app.descendants(matching: .any)["map.timing"]
        let rendered = NSPredicate(format: "label CONTAINS 'fully rendered' AND NOT (label CONTAINS 'pending')")
        let timing = XCTNSPredicateExpectation(predicate: rendered, object: timingElement)
        XCTAssertEqual(XCTWaiter().wait(for: [timing], timeout: 20), .completed, "map never fully rendered: \(timingElement.label)")
        print("MAP_TIMING tab to map: \(timingElement.label)")

        setPlace(app, "38.3740, -109.9654")

        let place = app.staticTexts["map.placeLabel"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        XCTAssertTrue(place.label.contains("38.3740, -109.9654"), place.label)

        let summary = app.otherElements["map.lineSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        for text in ["Sun set", "Sun rise", "Moon", "GC"] {
            XCTAssertTrue(summary.label.contains(text), "missing \(text) in \(summary.label)")
        }

        let scrubber = app.otherElements["map.scrubber"]
        XCTAssertTrue(scrubber.exists)
        let before = scrubber.value as? String
        app.buttons["10 minutes later"].tap()
        XCTAssertNotEqual(scrubber.value as? String, before, "scrubber did not move")
    }

    @MainActor
    func testBadCoordinatesAreRejected() {
        let app = openMap()
        setPlace(app, "91, 10")
        XCTAssertTrue(app.staticTexts["Enter latitude and longitude in degrees, e.g. 38.3740, -109.9654."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["map.placeLabel"].exists)
    }

    @MainActor
    func testLayerTogglesLiveOutsideTheMap() {
        let app = openMap()
        let smoke = app.descendants(matching: .any)["layer.smoke"]
        XCTAssertTrue(smoke.waitForExistence(timeout: 10))
        let before = smoke.value as? String
        smoke.tap()
        XCTAssertNotEqual(smoke.value as? String, before)
        smoke.tap()
        XCTAssertEqual(smoke.value as? String, before)
    }

    /// Screenshots for the owner's visual check in both modes; runs only with
    /// `TEST_RUNNER_MAP_SCREENSHOTS=1` and keeps them in the result bundle.
    @MainActor
    func testScreenshotsBothModes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MAP_SCREENSHOTS"] == "1", "set TEST_RUNNER_MAP_SCREENSHOTS=1")
        let app = openMap()
        setPlace(app, ProcessInfo.processInfo.environment["MAP_PLACE"] ?? "40.2500, -111.7500")
        if ProcessInfo.processInfo.environment["MAP_IR"] == "1" {
            app.descendants(matching: .any)["layer.infrared"].tap()
        }
        sleep(12)
        attach(app, "map-standard")
        app.buttons["Field mode"].firstMatch.tap()
        sleep(4)
        attach(app, "map-field")
        scrollPanel(app)
        sleep(1)
        attach(app, "map-field-panel")
        app.buttons["Field mode"].firstMatch.tap()
        sleep(2)
        attach(app, "map-standard-panel")
    }

    /// The published layers are on the phone after the first load (the
    /// fixture archives are a few KB, so this downloads almost nothing).
    @MainActor
    func testPublishedLayersKeptOffline() {
        let app = openMap()
        let lp = app.staticTexts["offline.lightPollution"]
        for _ in 0..<8 where !lp.exists || !lp.isHittable { scrollPanel(app) }
        let saved = NSPredicate(format: "label BEGINSWITH 'On this phone'")
        for id in ["offline.lightPollution", "offline.land", "offline.places"] {
            let e = app.staticTexts[id]
            let x = XCTNSPredicateExpectation(predicate: saved, object: e)
            XCTAssertEqual(XCTWaiter().wait(for: [x], timeout: 60), .completed, "\(id): \(e.label)")
        }
    }

    /// Drags the panel under the scrubber; the map above it never receives the gesture.
    @MainActor
    private func scrollPanel(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
