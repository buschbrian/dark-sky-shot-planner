import XCTest

/// Spots (M8) and horizon profiles (M9, app side). Set `TEST_RUNNER_DS_SHOTS`
/// to a folder to also save screenshots there for a visual check.
final class SpotsTests: XCTestCase {
    static let camp = (lat: "38.374031", lon: "-109.965416")

    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Offline UI-test mode (no network, no remembered place); stubs pick the conditions outcome.
        let stub = name.contains("GoNight") ? ["-stubConditions", "go"]
            : name.contains("Unavailable") ? ["-stubConditions", "unavailable"] : []
        app.launchArguments = ["-DarkSkyUITest", "-resetSpots", "-FieldMode", "NO"] + stub
        app.launch()
        app.tabBars.buttons["Spots"].tap()
    }

    @MainActor
    func testCreateEditUseAndDeleteSpot() {
        addSpot(name: "Test Ridge", lat: "38.5", lon: "-109.6")
        let row = app.buttons["spot-row-Test Ridge"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        app.buttons["edit-spot"].tap()
        let name = app.textFields["spot-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" North")
        app.buttons["spot-save"].tap()
        XCTAssertTrue(app.navigationBars["Test Ridge North"].waitForExistence(timeout: 5))
        XCTAssertFalse(any(label: "Not checked yet").exists, "a rename keeps the checked week")

        app.buttons["use-spot"].tap()
        XCTAssertTrue(app.buttons["In use on Tonight and Week"].waitForExistence(timeout: 5))

        // The week strip fills from SkyCore even with conditions unavailable.
        XCTAssertTrue(el("night-minutes").waitForExistence(timeout: 30))

        let delete = app.buttons["delete-spot"]
        delete.swipeUpUntilVisible(in: app)
        delete.tap()
        app.buttons["delete-spot"].tap()
        XCTAssertTrue(app.buttons["add-first-spot"].waitForExistence(timeout: 5), "list is empty again")
    }

    @MainActor
    func testMeasuredCandlestickProfile() {
        addSpot(name: "Candlestick Camp", lat: Self.camp.lat, lon: Self.camp.lon)
        app.buttons["spot-row-Candlestick Camp"].tap()
        let measured = app.buttons["horizon-measured"]
        measured.swipeUpUntilVisible(in: app)
        measured.tap()
        XCTAssertTrue(el("skyline-chart").waitForExistence(timeout: 5))
        let minutes = el("night-minutes")
        app.swipeDown()
        XCTAssertTrue(minutes.waitForExistence(timeout: 30))
        XCTAssertTrue(waitFor(minutes, labelContains: "above the skyline", timeout: 30), minutes.label)
        shot("spot-detail-measured")
    }

    @MainActor
    func testAlertRuleShowsLastChecked() {
        addSpot(name: "Alert Flat", lat: "38.2", lon: "-110.1")
        app.buttons["spot-row-Alert Flat"].tap()
        let toggle = el("alert-toggle")
        toggle.swipeUpUntilVisible(in: app)
        toggle.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(el("alert-last-checked").waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        // The list is lazy: the spot's shot-window line sits above, so bring "Check now" on screen first.
        let check = el("alert-check-now")
        check.swipeUpUntilVisible(in: app)
        XCTAssertTrue(check.exists)
        shot("spot-alert")
    }

    /// A stub provider with every gating factor good (DEBUG `-stubConditions go`)
    /// makes a Go night, and the check posts the alert: nights are marked
    /// "Alerted for" only after iOS accepts the notification. Needs a night
    /// with ≥ 120 moon-free minutes this week (true on all but a few nights
    /// either side of full moon at Candlestick).
    @MainActor
    func testGoNightFromStubProviderPostsAlert() {
        enableAlert(at: "Candlestick Camp", lat: Self.camp.lat, lon: Self.camp.lon)
        let notified = el("alert-notified")
        XCTAssertTrue(notified.waitForExistence(timeout: 60), "no Go night alerted")
        XCTAssertTrue(el("alert-last-checked").label.hasPrefix("Checked"), el("alert-last-checked").label)
        shot("spot-alert-go")
    }

    /// With no usable conditions the check records "couldn't check", never
    /// "checked, no Go night", and alerts nothing.
    @MainActor
    func testUnavailableProviderRecordsCouldntCheck() {
        enableAlert(at: "Candlestick Camp", lat: Self.camp.lat, lon: Self.camp.lon)
        let status = el("alert-last-checked")
        XCTAssertTrue(waitFor(status, labelContains: "Couldn't check", timeout: 60), status.label)
        XCTAssertTrue(status.label.contains("Conditions unavailable"), status.label)
        XCTAssertFalse(el("alert-notified").exists)
        shot("spot-alert-unavailable")
    }

    /// ios/AGENTS.md invariant 5 over this screen's content: no pixel with a
    /// lit green or blue channel between the navigation bar and the tab bar.
    @MainActor
    func testFieldModeHasNoWhiteOrBluePixels() throws {
        addSpot(name: "Candlestick Camp", lat: Self.camp.lat, lon: Self.camp.lon)
        app.buttons["spot-row-Candlestick Camp"].tap()
        let measured = app.buttons["horizon-measured"]
        measured.swipeUpUntilVisible(in: app)
        measured.tap()
        app.swipeDown()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        shot("spots-list-standard")
        app.buttons["Field mode"].firstMatch.tap()
        shot("spots-list-field")
        try assertRedOnly("list")
        app.buttons["add-spot"].tap()
        XCTAssertTrue(app.textFields["spot-name"].waitForExistence(timeout: 5))
        shot("spot-editor-field")
        try assertRedOnly("editor")
        app.buttons["Cancel"].tap()
        app.buttons["spot-row-Candlestick Camp"].tap()
        XCTAssertTrue(el("night-minutes").waitForExistence(timeout: 30))
        shot("spot-detail-field-top")
        try assertRedOnly("detail top")
        app.swipeUp()
        shot("spot-detail-field-middle")
        try assertRedOnly("detail middle")
        app.swipeUp()
        app.swipeUp()
        shot("spot-detail-field-bottom")
        try assertRedOnly("detail bottom")
    }

    /// M9 end to end: download real AWS Terrain Tiles, decode with ImageIO,
    /// ray-march, and compare with the measured Candlestick skyline. Needs network.
    @MainActor
    func testComputedCandlestickMatchesMeasured() throws {
        addSpot(name: "Candlestick Camp", lat: Self.camp.lat, lon: Self.camp.lon)
        app.buttons["spot-row-Candlestick Camp"].tap()
        let compute = app.buttons["horizon-compute"]
        compute.swipeUpUntilVisible(in: app)
        compute.tap()
        let rms = el("horizon-rms")
        let failed = el("horizon-error")
        let deadline = Date.now.addingTimeInterval(240)
        while Date.now < deadline, !rms.exists, !failed.exists { _ = rms.waitForExistence(timeout: 2) }
        if failed.exists { throw XCTSkip("terrain unavailable: \(failed.label)") }
        XCTAssertTrue(rms.exists, "no RMS after 240 s")
        rms.swipeUpUntilVisible(in: app)
        shot("spot-horizon-computed")
        let value = try XCTUnwrap(Double(rms.label.components(separatedBy: "RMS ")[1].prefix { $0 != "°" }))
        print("DS_COMPUTED_RMS \(rms.label)")
        print("DS_COMPUTED_SOURCE \(any(labelContains: "Computed on this phone").label)")
        XCTAssertLessThan(value, 0.5, rms.label)
    }

    // MARK: Helpers

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func any(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func any(labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func addSpot(name: String, lat: String, lon: String) {
        let first = app.buttons["add-first-spot"]
        (first.waitForExistence(timeout: 3) ? first : app.buttons["add-spot"]).tap()
        let nameField = app.textFields["spot-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.textFields["spot-latitude"].tap()
        app.textFields["spot-latitude"].typeText(lat)
        app.textFields["spot-longitude"].tap()
        app.textFields["spot-longitude"].typeText(lon)
        app.buttons["spot-save"].tap()
        XCTAssertTrue(app.buttons["spot-row-\(name)"].waitForExistence(timeout: 5))
    }

    /// Adds a spot, turns its Go alert on (allowing notifications) and taps Check now.
    func enableAlert(at name: String, lat: String, lon: String) {
        addSpot(name: name, lat: lat, lon: lon)
        app.buttons["spot-row-\(name)"].tap()
        let toggle = el("alert-toggle")
        toggle.swipeUpUntilVisible(in: app)
        toggle.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let check = el("alert-check-now")
        check.swipeUpUntilVisible(in: app)
        check.tap()
    }

    func waitFor(_ element: XCUIElement, labelContains text: String, timeout: TimeInterval) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: p, object: element)], timeout: timeout) == .completed
    }

    func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["DS_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Scans the region between the navigation bar and the tab bar (in field
    /// mode, the palette dock that replaces it). Pixels are
    /// allowed any red; green and blue must stay dark (≤ 24 of 255).
    func assertRedOnly(_ label: String) throws {
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { throw XCTSkip("no CGImage") }
        let nav = app.navigationBars.firstMatch.frame
        // Field mode hides the system tab bar; the dock's brightness row is its top.
        let dock = el("field.brightness")
        let tabs = dock.exists ? dock.frame : app.tabBars.firstMatch.frame
        let scale = CGFloat(cg.height) / app.frame.height
        let top = Int((nav.maxY + 1) * scale)
        let bottom = Int((tabs.minY - 1) * scale)
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        XCTAssertGreaterThan(bottom - top, height / 3, "\(label): scan region collapsed")
        var bad = 0
        var example = ""
        for y in top..<max(top, bottom) {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixels[i + 1] > 24 || pixels[i + 2] > 24 {
                    if bad == 0 { example = "(\(x), \(y)) rgb \(pixels[i]) \(pixels[i + 1]) \(pixels[i + 2])" }
                    bad += 1
                }
            }
        }
        XCTAssertEqual(bad, 0, "\(label): \(bad) non-red pixels, first at \(example)")
    }
}

extension XCUIElement {
    /// Slow swipes so a lazy List does not scroll the element past and recycle
    /// it; if it did go above the middle, come back down.
    func swipeUpUntilVisible(in app: XCUIApplication, attempts: Int = 10) {
        var n = 0
        while !(exists && isHittable) && n < attempts {
            if exists, frame.maxY < app.frame.midY { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            n += 1
        }
    }
}
