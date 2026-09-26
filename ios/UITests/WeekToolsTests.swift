import XCTest

/// M5 Week and M10 Tools. Debug-only launch hooks: `DS_PLACE`,
/// `DS_FIXTURE_CONDITIONS` (App/Week/WeekDebug.swift), `DS_RESET_GEAR` (ToolsScreen).
final class WeekToolsTests: XCTestCase {
    static let canyonlands = "Canyonlands Needles|38.15|-109.75|America/Denver"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ env: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = env
        // The shared UI-test mode: no network, throwaway conditions cache, no remembered place.
        app.launchArguments = ["-DarkSkyUITest"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func openWeek(_ app: XCUIApplication) {
        XCTAssertTrue(app.segmentedControls.buttons["Week"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Week"].tap()
    }

    @MainActor
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func toggleFieldMode(_ app: XCUIApplication) {
        let toggle = app.buttons["Field mode"].firstMatch.exists ? app.buttons["Field mode"].firstMatch : app.switches["Field mode"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
    }

    @MainActor
    func testWeekWithoutPlaceAsksForOne() {
        let app = launch()
        openWeek(app)
        XCTAssertTrue(element(app, containing: "Choose a place first").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, containing: "moon-free").exists, "no table without a place")
        snapshot("week-no-place")
    }

    @MainActor
    func testWeekWithoutConditionsReadsUnavailable() {
        let app = launch(["DS_PLACE": Self.canyonlands])
        openWeek(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(rows.count, 7)
        let status = app.staticTexts["week.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let done = NSPredicate(format: "label CONTAINS 'Conditions unavailable'")
        expectation(for: done, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(element(app, containing: "Cloud unavailable").exists || element(app, containing: "no moon-free darkness").exists)
        XCTAssertFalse(element(app, containing: "Cloud mean 0%").exists, "missing cloud must never read as 0%")
        XCTAssertTrue(element(app, containing: "Aurora unavailable: no Kp data").exists)
    }

    @MainActor
    func testWeekRowsWithConditionsOpenTonight() {
        let app = launch(["DS_PLACE": Self.canyonlands, "DS_FIXTURE_CONDITIONS": "1"])
        openWeek(app)
        let status = app.staticTexts["week.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Conditions received'"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week.row.'"))
        XCTAssertEqual(rows.count, 7)
        XCTAssertTrue(element(app, containing: "across 4 models").exists || element(app, containing: "across 3 models").exists)
        XCTAssertTrue(element(app, containing: "Open-Meteo").exists, "cloud numbers carry their source")
        snapshot("week-standard-top")
        app.swipeUp()
        XCTAssertTrue(element(app, containing: "Aurora possible").exists, "Kp 8 fixture night flags aurora")
        snapshot("week-standard-bottom")
        app.swipeDown()

        toggleFieldMode(app)
        snapshot("week-field-top")
        app.swipeUp()
        snapshot("week-field-bottom")
        toggleFieldMode(app)
        app.swipeDown()

        // Switch away and back: the cached week must draw its rows at once.
        app.segmentedControls.buttons["Tonight"].tap()
        let started = Date()
        app.segmentedControls.buttons["Week"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let seconds = Date().timeIntervalSince(started)
        add(XCTAttachment(string: "Week rows visible \(Int(seconds * 1000)) ms after switching back (XCUITest wall clock)"))

        rows.element(boundBy: 1).tap()
        XCTAssertTrue(app.segmentedControls.buttons["Tonight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Tonight"].isSelected, "a Week row opens that night in Tonight")
    }

    /// Enters a number with the in-app keypad (the field's input view).
    @MainActor
    private func enter(_ app: XCUIApplication, _ id: String, _ value: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing field \(id)")
        field.tap()
        XCTAssertTrue(app.keys["keypad.done"].waitForExistence(timeout: 5))
        for _ in 0..<(field.value as? String ?? "").count { app.keys["keypad.delete"].tap() }
        for ch in value {
            let key = switch ch {
            case ".": "keypad.point"
            case "-": "keypad.sign"
            default: "keypad.\(ch)"
            }
            app.keys[key].tap()
        }
        app.keys["keypad.done"].tap()
    }

    @MainActor
    func testGearAndNPFCalculatorWalkthrough() {
        let app = launch(["DS_RESET_GEAR": "1"])
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(element(app, containing: "No gear yet").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tools.calc.starExposure"].exists, "calculators need gear")

        app.buttons["tools.addGear"].tap()
        let cameraName = app.textFields["gear.cameraName"]
        XCTAssertTrue(cameraName.waitForExistence(timeout: 5))
        cameraName.tap()
        cameraName.typeText("Sony A7 III")
        enter(app, "gear.sensorWidth", "35.6")
        enter(app, "gear.sensorHeight", "23.8")
        enter(app, "gear.imageWidth", "6000")
        enter(app, "gear.imageHeight", "4000")
        let lensName = app.textFields["gear.lensName"]
        lensName.tap()
        lensName.typeText("Sigma 20mm Art")
        enter(app, "gear.focalLength", "20")
        XCTAssertTrue(element(app, containing: "Enter a number").exists, "an empty aperture shows the typed error")
        XCTAssertFalse(app.buttons["gear.save"].isEnabled)
        enter(app, "gear.maxAperture", "1.4")
        XCTAssertTrue(app.buttons["gear.save"].isEnabled)
        app.buttons["gear.save"].tap()

        XCTAssertTrue(element(app, containing: "Sony A7 III + Sigma 20mm Art").waitForExistence(timeout: 5))
        snapshot("tools-standard")
        app.buttons["tools.calc.starExposure"].tap()

        // Complete NPF, k = 2, f/1.4, 20 mm, 35.6 mm / 6000 px = 5.933 µm, δ = −29.0°:
        // 2·(16.856·1.4 + 0.0997·20 + 13.713·5.933)/(20·cos 29.0°) = 12.23 s.
        // 500 rule: crop 43.27/42.82 = 1.0104, 500/(1.0104·20) = 24.74 s.
        let npf = app.descendants(matching: .any)["tools.result.npf"].firstMatch
        XCTAssertTrue(npf.waitForExistence(timeout: 5))
        XCTAssertTrue(npf.label.contains("12.2 s"), npf.label)
        XCTAssertTrue(app.descendants(matching: .any)["tools.result.500"].firstMatch.label.contains("24.7 s"))
        XCTAssertTrue(element(app, containing: "Michaud").exists, "NPF credits Michaud / SAH")

        app.buttons["tools.k.1 strict"].tap()
        XCTAssertTrue(npf.label.contains("6.1 s"), npf.label)

        enter(app, "tools.declination", "95")
        XCTAssertTrue(element(app, containing: "Declination must be between").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, containing: "nan").exists)
        XCTAssertFalse(element(app, containing: "NaN").exists)
        snapshot("tools-npf-error")

        enter(app, "tools.fNumber", "1")
        XCTAssertTrue(element(app, containing: "wider than this lens opens").waitForExistence(timeout: 5))

        app.buttons["Use Galactic Center"].tap()
        enter(app, "tools.fNumber", "2.8")
        XCTAssertEqual(app.textFields["tools.fNumber"].value as? String, "2.8")
        XCTAssertTrue(npf.label.contains("7.5 s"), npf.label)
        snapshot("tools-npf-standard")

        toggleFieldMode(app)
        snapshot("tools-npf-field")
        app.textFields["tools.fNumber"].tap()
        snapshot("tools-keypad-field")
        app.keys["keypad.done"].tap()
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["tools.calc.starExposure"].waitForExistence(timeout: 5))
        snapshot("tools-field")
    }

    @MainActor
    func testAccessibilityTextSize() {
        let app = launch(["DS_PLACE": Self.canyonlands, "DS_FIXTURE_CONDITIONS": "1"],
                         arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openWeek(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(rows.count, 7)
        XCTAssertTrue(rows.firstMatch.label.contains("moon-free"), "a row reads as one VoiceOver element")
        snapshot("week-ax-large")
        app.tabBars.buttons["Tools"].tap()
        snapshot("tools-ax-large")
    }
}
