import XCTest

/// The design pass's evidence: every tab and sheet in standard and field mode,
/// kept as attachments (and written to `TEST_RUNNER_DS_SHOTS` when set), with
/// the field-mode pixel rule checked on each field screen: no pixel with a
/// green or blue channel above 12 (ios/AGENTS.md invariant 5).
final class DesignTourTests: XCTestCase {
    static let place = "Canyonlands Needles|38.15|-109.75|America/Denver"
    static let camp = (lat: "38.374031", lon: "-109.965416")

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(field: Bool, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["DS_PLACE": Self.place, "DS_FIXTURE_CONDITIONS": "1"]
        app.launchArguments = ["-DarkSkyUITest", "-FieldMode", field ? "YES" : "NO"] + extra
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Tonight (three scroll positions), every factor, the calendar, Location and Week.
    @MainActor
    func testNightTabTour() throws {
        for field in [false, true] {
            let app = launch(field: field)
            let m = field ? "field" : "std"
            XCTAssertTrue(el(app, "tonight.headline").waitForExistence(timeout: 20))
            _ = el(app, "tonight.conditionsStrip").waitForExistence(timeout: 10)
            // Review B-3: the shot plan is the first block, so the field scan covers it.
            XCTAssertTrue(el(app, "shot.target").waitForExistence(timeout: 10))
            XCTAssertTrue(el(app, "shot.target").isHittable, "shot plan on screen in tonight-1")
            try shot(app, "tonight-1-\(m)", field: field)
            app.swipeUp()
            try shot(app, "tonight-2-\(m)", field: field)
            app.swipeUp()
            app.swipeUp()
            try shot(app, "tonight-3-\(m)", field: field)
            app.swipeDown()
            app.swipeDown()
            app.swipeDown()
            el(app, "tonight.factors").tap()
            XCTAssertTrue(el(app, "factors.done").waitForExistence(timeout: 5))
            try shot(app, "factors-\(m)", field: field)
            el(app, "factors.done").tap()
            el(app, "tonight.date").tap()
            XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 5))
            try shot(app, "calendar-\(m)", field: field)
            app.buttons["Cancel"].firstMatch.tap()
            el(app, "tonight.location").tap()
            XCTAssertTrue(el(app, "location.cancel").waitForExistence(timeout: 5))
            try shot(app, "location-\(m)", field: field)
            el(app, "location.cancel").tap()
            // The events section and the collapsed conditions rows, in both palettes.
            let events = el(app, "skyEvents.section")
            events.swipeUpUntilVisible(in: app)
            try shot(app, "tonight-events-\(m)", field: field)
            let strip = el(app, "tonight.conditionsStrip")
            strip.swipeUpUntilVisible(in: app)
            try shot(app, "tonight-conditions-\(m)", field: field)
            for _ in 0..<6 { app.swipeDown() }
            if field { app.buttons["scope.week"].tap() } else { app.segmentedControls.buttons["Week"].tap() }
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week.row.'"))
                .firstMatch.waitForExistence(timeout: 15))
            sleep(2)
            try shot(app, "week-\(m)", field: field)
            app.terminate()
        }
    }

    @MainActor
    func testMapTour() throws {
        for field in [false, true] {
            let app = launch(field: field, extra: ["-resetMapState"])
            tab(app, "Map", field: field)
            XCTAssertTrue(el(app, "map.placeLabel").waitForExistence(timeout: 15))
            sleep(6)
            let m = field ? "field" : "std"
            try shot(app, "map-1-\(m)", field: field)
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            sleep(1)
            try shot(app, "map-2-\(m)", field: field)
            app.terminate()
        }
    }

    /// Spots list, a spot's detail with its skyline and alert, and the editor.
    /// The spot is created in standard mode (the system keyboard is not red).
    @MainActor
    func testSpotsTour() throws {
        let app = launch(field: false, extra: ["-resetSpots"])
        app.tabBars.buttons["Spots"].tap()
        XCTAssertTrue(app.buttons["add-first-spot"].waitForExistence(timeout: 5))
        try shot(app, "spots-empty-std", field: false)
        app.buttons["add-first-spot"].tap()
        let name = app.textFields["spot-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Candlestick Camp")
        app.textFields["spot-latitude"].tap()
        app.textFields["spot-latitude"].typeText(Self.camp.lat)
        app.textFields["spot-longitude"].tap()
        app.textFields["spot-longitude"].typeText(Self.camp.lon)
        try shot(app, "spot-editor-std", field: false)
        app.buttons["spot-save"].tap()
        app.buttons["spot-row-Candlestick Camp"].tap()
        let measured = app.buttons["horizon-measured"]
        measured.swipeUpUntilVisible(in: app)
        measured.tap()
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(el(app, "night-minutes").waitForExistence(timeout: 30))
        app.terminate()

        for field in [false, true] {
            let app = launch(field: field)
            let m = field ? "field" : "std"
            tab(app, "Spots", field: field)
            XCTAssertTrue(app.buttons["spot-row-Candlestick Camp"].waitForExistence(timeout: 5))
            XCTAssertFalse(el(app, "icloud-sync").exists, "sync lives in Tools > About, not the Spots list")
            try shot(app, "spots-\(m)", field: field)
            app.buttons["spot-row-Candlestick Camp"].tap()
            XCTAssertTrue(el(app, "night-minutes").waitForExistence(timeout: 30))
            // Review B-7: field mode toggles from the pushed spot page, last on the right.
            let toggle = app.buttons["Field mode"].firstMatch
            XCTAssertTrue(toggle.exists, "field-mode toggle on the pushed spot page")
            XCTAssertGreaterThan(toggle.frame.midX, app.frame.midX, "toggle on the right")
            XCTAssertEqual(toggle.value as? String, field ? "On" : "Off")
            // A moon-limited night shows the moon, not the red cross.
            let nights = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'night-2' AND label CONTAINS ': ' AND label CONTAINS ', 0 minutes moon-free'"))
            for i in 0..<nights.count {
                XCTAssertTrue(nights.element(boundBy: i).label.contains("moon up"), nights.element(boundBy: i).label)
            }
            try shot(app, "spot-detail-1-\(m)", field: field)
            app.swipeUp()
            try shot(app, "spot-detail-2-\(m)", field: field)
            let alert = el(app, "alert-toggle")
            alert.swipeUpUntilVisible(in: app)
            try shot(app, "alerts-\(m)", field: field)
            app.terminate()
        }
    }

    /// Tools with a gear profile and the NPF calculator.
    @MainActor
    func testToolsTour() throws {
        let setup = XCUIApplication()
        setup.launchEnvironment = ["DS_RESET_GEAR": "1"]
        setup.launchArguments = ["-DarkSkyUITest", "-FieldMode", "NO"]
        setup.launch()
        setup.tabBars.buttons["Tools"].tap()
        setup.buttons["tools.addGear"].tap()
        let camera = setup.textFields["gear.cameraName"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        camera.tap()
        camera.typeText("Sony A7 III")
        for (id, v) in [("gear.sensorWidth", "35.6"), ("gear.sensorHeight", "23.8"), ("gear.imageWidth", "6000"),
                        ("gear.imageHeight", "4000"), ("gear.focalLength", "20"), ("gear.maxAperture", "1.4")] {
            enter(setup, id, v)
        }
        try shot(setup, "gear-editor-std", field: false)
        // The sheet has the field-mode toggle; in field mode names are read-only (system keyboard).
        let sheetToggle = setup.buttons["Field mode"].firstMatch
        XCTAssertTrue(sheetToggle.exists, "field-mode toggle in the gear sheet")
        sheetToggle.tap()
        XCTAssertFalse(camera.isEnabled, "names are read-only in field mode")
        try shot(setup, "gear-editor-field", field: true)
        sheetToggle.tap()
        XCTAssertTrue(camera.isEnabled)
        setup.buttons["gear.save"].tap()
        setup.terminate()

        for field in [false, true] {
            let app = launch(field: field)
            let m = field ? "field" : "std"
            tab(app, "Tools", field: field)
            XCTAssertTrue(app.buttons["tools.calc.starExposure"].waitForExistence(timeout: 5))
            try shot(app, "tools-\(m)", field: field)
            if !field {
                // The not-yet-built iCloud sync lives on the About page.
                let about = app.buttons["tools.about"]
                about.swipeUpUntilVisible(in: app)
                about.tap()
                XCTAssertTrue(el(app, "icloud-sync").waitForExistence(timeout: 5))
                try shot(app, "about-\(m)", field: field)
                app.navigationBars.buttons.element(boundBy: 0).tap()
                app.swipeDown()
            }
            app.buttons["tools.calc.starExposure"].tap()
            XCTAssertTrue(el(app, "tools.result.npf").waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Field mode"].firstMatch.exists, "field-mode toggle on the pushed calculator")
            try shot(app, "tools-npf-\(m)", field: field)
            app.textFields["tools.fNumber"].tap()
            XCTAssertTrue(app.keys["keypad.done"].waitForExistence(timeout: 5))
            try shot(app, "tools-keypad-\(m)", field: field)
            app.keys["keypad.done"].tap()
            app.terminate()
        }
    }

    /// The design gallery in both palettes.
    @MainActor
    func testGallery() throws {
        for field in [false, true] {
            let app = launch(field: field, extra: ["-DSTab", "gallery"])
            XCTAssertTrue(app.staticTexts["Design"].firstMatch.waitForExistence(timeout: 10))
            try shot(app, "gallery-\(field ? "field" : "std")", field: field)
            app.terminate()
        }
    }

    /// Accessibility XL text: the headline value is whole on Tonight and Week.
    @MainActor
    func testAccessibilityXL() throws {
        let app = launch(field: false, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let headline = el(app, "tonight.headline")
        XCTAssertTrue(headline.waitForExistence(timeout: 20))
        for id in ["tonight.factors", "tonight.refresh"] {
            let b = app.buttons[id]
            b.swipeUpUntilVisible(in: app)
            XCTAssertTrue(b.exists, id)
            XCTAssertLessThanOrEqual(b.frame.maxX, app.frame.maxX - 16, "\(id) stays inside the card")
        }
        app.swipeDown(velocity: .slow)
        app.swipeDown(velocity: .slow)
        XCTAssertTrue(headline.label.contains("minutes of moon-free darkness"), headline.label)
        XCTAssertTrue(headline.frame.minX >= 0 && headline.frame.maxX <= app.frame.maxX + 1, "headline fits the width")
        try shot(app, "ax-tonight-1", field: false)
        // StatusBadge stacks its qualifier at accessibility sizes: one element, "No-go, incomplete data".
        let badge = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "^(Go|Marginal|No-go|Unavailable), .+")).firstMatch
        for _ in 0..<4 where !(badge.exists && badge.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(badge.exists, "stacked status badge at AX-XL")
        XCTAssertLessThanOrEqual(badge.frame.maxX, app.frame.maxX + 1, "badge fits the width")
        try shot(app, "ax-tonight-2", field: false)
        app.segmentedControls.buttons["Week"].tap()
        sleep(3)
        try shot(app, "ax-week", field: false)
        app.tabBars.buttons["Tools"].tap()
        try shot(app, "ax-tools", field: false)
        app.tabBars.buttons["Map"].tap()
        sleep(4)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        try shot(app, "ax-map", field: false)
    }

    /// Field mode is remembered across a real process relaunch, and the
    /// brightness control is on screen while it is on.
    @MainActor
    func testFieldModeSurvivesRelaunch() throws {
        func start() -> XCUIApplication {
            let app = XCUIApplication()
            app.launchEnvironment = ["DS_PLACE": Self.place]
            app.launchArguments = ["-DarkSkyUITest"]
            app.launch()
            return app
        }
        var app = start()
        let toggle = app.buttons["Field mode"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if (toggle.value as? String) == "On" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "Off")
        toggle.tap()
        XCTAssertTrue(el(app, "field.brightness").waitForExistence(timeout: 5), "brightness control in field mode")
        app.terminate()

        app = start()
        let again = app.buttons["Field mode"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(again.value as? String, "On", "field mode survives a relaunch")
        XCTAssertTrue(el(app, "fieldDock.tonight").exists)
        XCTAssertTrue(el(app, "tonight.headline").waitForExistence(timeout: 20))
        try shot(app, "relaunch-field", field: true)
        let slider = el(app, "field.brightness")
        slider.swipeLeft()
        again.tap()
        XCTAssertFalse(el(app, "field.brightness").exists)
        app.terminate()

        app = start()
        let off = app.buttons["Field mode"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 10))
        XCTAssertEqual(off.value as? String, "Off", "turning it off is remembered too")
    }

    // MARK: Helpers

    @MainActor
    private func tab(_ app: XCUIApplication, _ name: String, field: Bool) {
        if field { app.buttons["fieldDock.\(name.lowercased())"].tap() } else { app.tabBars.buttons[name].tap() }
    }

    @MainActor
    private func enter(_ app: XCUIApplication, _ id: String, _ value: String) {
        let field = app.textFields[id]
        field.swipeUpUntilVisible(in: app)
        field.tap()
        XCTAssertTrue(app.keys["keypad.done"].waitForExistence(timeout: 5))
        for ch in value {
            app.keys[ch == "." ? "keypad.point" : "keypad.\(ch)"].tap()
        }
        app.keys["keypad.done"].tap()
    }

    /// Attaches the screen and, in field mode, fails on any pixel with G or B above 12.
    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String, field: Bool) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: screenshot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["DS_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        guard field, let cg = screenshot.image.cgImage else { return }
        // The home indicator is iOS's: it only auto-hides, so its strip is skipped.
        let skipBottom = Int(34 * CGFloat(cg.height) / app.frame.height)
        let (bad, first) = Self.nonRed(cg, threshold: 12, skipBottomRows: skipBottom)
        let note = XCTAttachment(string: "\(name): \(bad) pixels with G or B > 12\(first.map { ", first \($0)" } ?? "")")
        note.name = "scan-\(name)"
        note.lifetime = .keepAlways
        add(note)
        print("DS_SCAN \(name) bad=\(bad)")
        XCTAssertEqual(bad, 0, "\(name): \(bad) non-red pixels, first \(first ?? "")")
    }

    static func nonRed(_ cg: CGImage, threshold: UInt8, skipBottomRows: Int = 0) -> (Int, String?) {
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var bad = 0
        var first: String?
        for i in stride(from: 0, to: (h - skipBottomRows) * w * 4, by: 4) where px[i + 1] > threshold || px[i + 2] > threshold {
            if first == nil { first = "(\((i / 4) % w), \((i / 4) / w)) rgb \(px[i]) \(px[i + 1]) \(px[i + 2])" }
            bad += 1
        }
        return (bad, first)
    }
}
