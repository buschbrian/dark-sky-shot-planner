import XCTest

/// The capture screen on the simulator, which has no camera: `-CaptureDemo`
/// loads the iPhone 18 Pro Max main camera as measured and canned run
/// states (CaptureModel+demo). Covers the fixed control bar, the label
/// fixes, the two-path guide, the results view and the Sky trail design.
/// Field-mode screenshots get the design tour's pixel rule (no G or B > 12).
final class CaptureScreenTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ demo: String, field: Bool = false, guideSeen: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["DS_PLACE": DesignTourTests.place, "DS_FIXTURE_CONDITIONS": "1"]
        app.launchArguments = ["-DarkSkyUITest", "-FieldMode", field ? "YES" : "NO", "-DSTab", "tools",
                               "-CaptureDemo", demo, "-capture.guideSeen", guideSeen ? "YES" : "NO"] + extra
        app.launch()
        let row = app.buttons["tools.capture"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.swipeUpUntilVisible(in: app)
        row.tap()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Scrolls the content until `element` sits fully above the bottom bar.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let bar = el(app, "capture.bar")
        for _ in 0..<14 {
            let barTop = bar.exists ? bar.frame.minY : app.frame.maxY
            if element.exists, element.frame.minY > 90, element.frame.maxY < barTop - 4 { return }
            if element.exists, element.frame.maxY >= barTop - 4 || !element.isHittable && element.frame.minY > app.frame.midY {
                app.swipeUp(velocity: .slow)
            } else if element.exists, element.frame.minY <= 90 {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
    }

    // MARK: 1. Controls within reach

    @MainActor
    func testStartStaysInReachWhileSettingsScroll() throws {
        let sizes: [(String, Bool, [String])] = [
            ("std", false, []),
            ("field", true, []),
            ("axl", false, ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]),
        ]
        for (name, field, extra) in sizes {
            let app = launch("setup", field: field, extra: extra)
            let start = app.buttons["capture.start"]
            XCTAssertTrue(start.waitForExistence(timeout: 10))
            XCTAssertTrue(start.isHittable, "\(name): Start is hittable without scrolling")
            XCTAssertGreaterThanOrEqual(start.frame.height.rounded(), 44, "\(name): Start is at least 44 pt tall")
            XCTAssertGreaterThan(start.frame.midY, app.frame.height * 0.6, "\(name): Start sits in the lower part of the screen")
            if field {
                let dock = el(app, "field.brightness")
                XCTAssertTrue(dock.exists)
                XCTAssertLessThanOrEqual(start.frame.maxY, dock.frame.minY, "Start sits above the field dock, not under it")
            }
            try shot(app, "capture-bar-\(name)", field: field)
            let y = start.frame.minY
            for _ in 0..<4 { app.swipeUp(velocity: .fast) }
            XCTAssertTrue(start.isHittable, "\(name): Start still hittable after scrolling the settings")
            XCTAssertEqual(start.frame.minY, y, accuracy: 1, "\(name): the bar does not move with the content")
            try shot(app, "capture-bar-scrolled-\(name)", field: field)
            app.terminate()
        }
    }

    // MARK: 2. Label fixes

    @MainActor
    func testExposureResolutionAndFocusLabels() throws {
        let app = launch("setup")
        let exposure = el(app, "capture.exposure")
        reveal(exposure, in: app)
        XCTAssertTrue(exposure.label.contains("1 s, the longest this camera allows"), exposure.label)
        let slider = app.sliders["capture.exposureSlider"]
        reveal(slider, in: app)
        slider.adjust(toNormalizedSliderPosition: 0.45)
        let lowered = el(app, "capture.exposure").label
        XCTAssertFalse(lowered.contains("longest"), lowered)
        XCTAssertTrue(lowered.range(of: #"0\.\d s; maximum 1 s"#, options: .regularExpression) != nil, lowered)
        try shot(app, "capture-exposure-lowered", field: false)

        // An explicit 12 MP / 48 MP choice, each with its storage.
        let twelve = app.buttons["capture.resolution.12 MP"]
        let fortyEight = app.buttons["capture.resolution.48 MP"]
        reveal(fortyEight, in: app)
        XCTAssertTrue(twelve.exists && fortyEight.exists)
        XCTAssertTrue((twelve.value as? String ?? "").contains("a frame"), "\(twelve.value ?? "")")
        XCTAssertTrue((fortyEight.value as? String ?? "").contains("a frame"), "\(fortyEight.value ?? "")")
        XCTAssertTrue(twelve.isSelected, "12 MP is the default")
        fortyEight.tap()
        XCTAssertTrue(fortyEight.isSelected)
        XCTAssertTrue(app.buttons["capture.format.ProRAW (DNG)"].exists, "RAW is named ProRAW when that is the format")
        try shot(app, "capture-resolution", field: false)

        // Focus steps: named, and at least 44 × 44 pt.
        let farther = app.buttons["capture.focus.slightlyFarther"]
        reveal(farther, in: app)
        XCTAssertEqual(farther.label, "Focus slightly farther")
        for id in ["nearer", "farther", "slightlyNearer", "slightlyFarther"] {
            let b = app.buttons["capture.focus.\(id)"]
            XCTAssertTrue(b.exists, id)
            XCTAssertGreaterThanOrEqual(b.frame.height.rounded(), 44, id)
            XCTAssertGreaterThanOrEqual(b.frame.width.rounded(), 44, id)
        }
        let before = el(app, "capture.focus.position").label
        farther.tap()
        XCTAssertNotEqual(el(app, "capture.focus.position").label, before, "the step moves the lens position")
        XCTAssertTrue(el(app, "capture.focus.hfr").label.contains("px"))
        try shot(app, "capture-focus", field: false)
    }

    // MARK: 3. Guided setup

    @MainActor
    func testGuideOnFirstOpenAndFromHowToShoot() throws {
        for field in [false, true] {
            let app = launch("setup", field: field, guideSeen: false)
            let m = field ? "field" : "std"
            let done = app.buttons["capture.guide.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10), "the guide opens the first time")
            let apple = el(app, "capture.guide.apple")
            XCTAssertTrue(apple.exists)
            for text in ["Live Photos", "Max", "ProRAW", "no fixed length"] {
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists, text)
            }
            try shot(app, "capture-guide-apple-\(m)", field: field)
            let night = app.links["capture.guide.nightModeLink"].firstMatch
            night.swipeUpUntilVisible(in: app)
            XCTAssertTrue(night.exists)
            XCTAssertTrue(app.links["capture.guide.proRAWLink"].firstMatch.exists)

            app.buttons["capture.guide.path.Capture and stack in Dark Sky"].firstMatch.swipeDownUntilVisible(in: app)
            app.buttons["capture.guide.path.Capture and stack in Dark Sky"].tap()
            let ceiling = el(app, "capture.guide.ceiling")
            XCTAssertTrue(ceiling.waitForExistence(timeout: 5))
            XCTAssertTrue(ceiling.label.contains("1 s per frame: what this iPhone reports"), ceiling.label)
            XCTAssertTrue(ceiling.label.contains("Other iPhones or iOS versions may allow a different length"), ceiling.label)
            for term in ["Exposure per frame", "Total exposure", "Sequence time", "Star-trailing limit (NPF)"] {
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", term)).firstMatch.exists, term)
            }
            try shot(app, "capture-guide-darksky-\(m)", field: field)
            let focus = app.staticTexts["capture.guide.focus"]
            focus.swipeUpUntilVisible(in: app)
            XCTAssertTrue(focus.exists)
            XCTAssertEqual(focus.label, "Make the star as small and sharp as possible.")
            try shot(app, "capture-guide-darksky-2-\(m)", field: field)
            let preset = app.buttons["capture.guide.usePreset"]
            preset.swipeDownUntilVisible(in: app)
            preset.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 5), "the preset closes the guide")
            XCTAssertTrue(app.buttons["capture.start"].label.contains("9 frames"), app.buttons["capture.start"].label)
            app.buttons["capture.howTo"].tap()
            XCTAssertTrue(done.waitForExistence(timeout: 5), "How to shoot opens the guide again")
            done.tap()
            app.terminate()
        }
    }

    // MARK: 4. During and after a run

    @MainActor
    func testRunThenResultsWithSaveImageFirst() throws {
        for field in [false, true] {
            let app = launch("setup", field: field)
            let m = field ? "field" : "std"
            XCTAssertTrue(app.buttons["capture.start"].waitForExistence(timeout: 10))
            let startLabel = app.buttons["capture.start"].label
            let planned = Int(startLabel.split(separator: " ").compactMap { Int($0) }.first ?? -1)
            XCTAssertGreaterThan(planned, 3, startLabel)
            app.buttons["capture.start"].tap()
            let stop = app.buttons["capture.stopAndStack"]
            let cancel = app.buttons["capture.cancel"]
            XCTAssertTrue(stop.waitForExistence(timeout: 15))
            XCTAssertTrue(stop.isHittable && cancel.isHittable, "both stop choices in reach")
            XCTAssertNotEqual(stop.label, cancel.label)
            XCTAssertFalse(app.sliders["capture.exposureSlider"].exists, "no editable settings during a run")
            XCTAssertTrue(el(app, "capture.run.settings").exists)
            XCTAssertTrue(el(app, "capture.bar.detail").label.contains("elapsed"))
            try shot(app, "capture-running-\(m)", field: field)

            stop.tap()
            let image = el(app, "capture.result.image")
            XCTAssertTrue(image.waitForExistence(timeout: 15), "the results view shows the stacked image")
            // The demo run keeps every frame and leaves 3 out of the stack.
            XCTAssertTrue(el(app, "capture.result.saved").label.hasSuffix("\(planned)"), el(app, "capture.result.saved").label)
            XCTAssertTrue(el(app, "capture.result.aligned").label.hasSuffix("\(planned - 3)"), el(app, "capture.result.aligned").label)
            XCTAssertTrue(el(app, "capture.result.rejected").label.hasSuffix("3"), el(app, "capture.result.rejected").label)
            XCTAssertFalse(el(app, "capture.result.unaligned").exists)
            let saveImage = app.buttons["capture.result.saveImage"]
            let saveAll = app.buttons["capture.result.saveOriginals"]
            XCTAssertTrue(saveImage.exists && saveAll.exists)
            XCTAssertLessThan(saveImage.frame.minY, saveAll.frame.minY, "Save image is first")
            XCTAssertTrue(el(app, "capture.result.method").label.contains("No AI denoise"))
            try shot(app, "capture-result-\(m)", field: field)
            saveImage.tap()
            XCTAssertTrue(el(app, "capture.result.message").waitForExistence(timeout: 5))
            XCTAssertTrue(el(app, "capture.result.message").label.contains("Saved the image"))
            saveAll.tap()
            XCTAssertTrue(el(app, "capture.result.message").label.contains("original frames"))
            app.buttons["capture.result.done"].tap()
            XCTAssertTrue(app.buttons["capture.showResult"].waitForExistence(timeout: 5), "the result stays one tap away")
            app.terminate()
        }
    }

    @MainActor
    func testCancelKeepsFramesWithoutStacking() {
        let app = launch("running")
        let cancel = app.buttons["capture.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        let status = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'not stacked'")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "capture.result.image").exists, "Cancel does not stack")
    }

    @MainActor
    func testUnalignedFallbackIsSaidPlainly() throws {
        let app = launch("unaligned")
        let notice = el(app, "capture.result.unaligned")
        XCTAssertTrue(notice.waitForExistence(timeout: 15))
        XCTAssertTrue(notice.label.contains("Not aligned on stars"), notice.label)
        XCTAssertTrue(el(app, "capture.result.aligned").label.contains("Averaged unaligned"))
        try shot(app, "capture-result-unaligned", field: false)
    }

    // MARK: 5. Star trails from the Sky design

    @MainActor
    func testStarTrailsReadTheSkyDesign() throws {
        // SkyTrailDesign JSON: 60 min of 29 s frames every 30 s, pole at (0.42, 0.18).
        let json = #"{"sequence":{"start":812000000,"exposure":29,"interval":30,"frames":120},"poleInFrame":[0.42,0.18]}"#
        let hex = json.utf8.map { String(format: "%02x", $0) }.joined()
        let app = launch("setup", extra: ["-sky.trailDesign", "<\(hex)>"])
        let trails = app.buttons["capture.mode.Star trails"]
        reveal(trails, in: app)
        trails.tap()
        let note = el(app, "capture.trailDesign")
        reveal(note, in: app)
        XCTAssertTrue(note.exists, "the Sky design is shown in star-trail mode")
        XCTAssertTrue(el(app, "capture.trails.duration").label.contains("60 min"), el(app, "capture.trails.duration").label)
        XCTAssertTrue(el(app, "capture.trails.interval").label.contains("1 s"), el(app, "capture.trails.interval").label)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '42 % across'")).firstMatch.exists)
        try shot(app, "capture-trails-design", field: false)
    }

    // MARK: Helpers

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
        let skipBottom = Int(34 * CGFloat(cg.height) / app.frame.height)
        let (bad, first) = DesignTourTests.nonRed(cg, threshold: 12, skipBottomRows: skipBottom)
        print("DS_SCAN \(name) bad=\(bad)")
        XCTAssertEqual(bad, 0, "\(name): \(bad) non-red pixels, first \(first ?? "")")
    }
}

extension XCUIElement {
    func swipeDownUntilVisible(in app: XCUIApplication, attempts: Int = 10) {
        var n = 0
        while !(exists && isHittable) && n < attempts {
            app.swipeDown(velocity: .slow)
            n += 1
        }
    }
}
