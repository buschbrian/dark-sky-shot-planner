import XCTest

/// Map tab (M6). The map fills the tab under a bottom sheet (review B-6); the
/// place can always be set without touching the map (invariant 5), and a
/// long-press only proposes a point (review B-9).
final class MapTests: XCTestCase {
    static let camp = "Candlestick Camp|38.374|-109.9654|America/Denver"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openMap(place: String? = nil, field: Bool = false, extra: [String] = [],
                         persist: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if let place { app.launchEnvironment["DS_PLACE"] = place }
        // -DarkSkyUITest: no remembered place from an earlier launch (review P2 #2).
        app.launchArguments = ["-DarkSkyUITest", "-resetMapState", "-FieldMode", field ? "YES" : "NO"]
            + (persist ? ["-DarkSkyUITestPersist"] : []) + extra
        app.launch()
        if field { app.buttons["fieldDock.map"].tap() } else { app.tabBars.buttons["Map"].tap() }
        XCTAssertTrue(app.otherElements["map.view"].waitForExistence(timeout: 15), "map view missing")
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func sheet(_ app: XCUIApplication, _ detent: String) {
        let grabber = app.buttons["map.sheet.grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 10))
        for _ in 0..<3 where (grabber.value as? String) != detent { grabber.tap(); usleep(400_000) }
        XCTAssertEqual(grabber.value as? String, detent)
    }

    @MainActor
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        // The panel is hidden from accessibility while the sheet is collapsed.
        sheet(app, "full height")
        XCTAssertTrue(e.waitForExistence(timeout: 10), "\(e) missing from the sheet")
        for _ in 0..<10 where !(e.exists && e.isHittable) {
            let s = app.otherElements["map.sheet"].frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: s.midX, dy: s.maxY - 120))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: s.midX, dy: s.minY + 160)))
        }
        if !e.isHittable {
            attach(app, "reveal-failed")
            print("REVEAL_FAILED sheet \(app.otherElements["map.sheet"].frame) element \(e.frame)")
            print(app.otherElements["map.sheet"].debugDescription.prefix(6000))
        }
        XCTAssertTrue(e.isHittable, "\(e) not reachable in the sheet")
    }

    @MainActor
    private func setPlace(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["map.coordinateField"]
        reveal(app, field)
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not appear")
        field.typeText(text)
        app.buttons["map.setPlace"].tap()
    }

    @MainActor
    private func waitLabel(_ e: XCUIElement, _ format: String, _ args: CVarArg..., timeout: TimeInterval = 10) -> Bool {
        let p = NSPredicate(format: format, argumentArray: args)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    // MARK: Place, lines, scrubber

    @MainActor
    func testMapLoadsAndCoordinateSetsPlaceWithoutTheMap() {
        let app = openMap()
        let timingElement = el(app, "map.timing")
        XCTAssertTrue(waitLabel(timingElement, "label CONTAINS 'fully rendered' AND NOT (label CONTAINS 'pending')", timeout: 20),
                      "map never fully rendered: \(timingElement.label)")
        print("MAP_TIMING tab to map: \(timingElement.label)")

        setPlace(app, "38.3740, -109.9654")
        let place = app.staticTexts["map.placeLabel"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        XCTAssertTrue(place.label.contains("38.3740, -109.9654"), place.label)

        // The target (the Galactic Core by default) is drawn; the full fan is the Compare view.
        let summary = el(app, "map.lineSummary")
        sheet(app, "full height")
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.hasPrefix("Core "), summary.label)
        XCTAssertFalse(summary.label.contains("Sun set"), summary.label)
        let compare = el(app, "map.compare")
        reveal(app, compare)
        compare.tap()
        XCTAssertTrue(waitLabel(summary, "label CONTAINS 'Sun set'"), summary.label)
        for text in ["Sun rise", "Moon", "GC"] {
            XCTAssertTrue(summary.label.contains(text), "missing \(text) in \(summary.label)")
        }

        let scrubber = el(app, "map.scrubber")
        reveal(app, scrubber)
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
        let smoke = el(app, "layer.smoke")
        reveal(app, smoke)
        let before = smoke.value as? String
        smoke.tap()
        XCTAssertNotEqual(smoke.value as? String, before)
        smoke.tap()
        XCTAssertEqual(smoke.value as? String, before)
        // The smoke row says what HMS holds, in the one voice.
        let status = el(app, "layer.smoke.status")
        XCTAssertTrue(waitLabel(status, "NOT (label BEGINSWITH 'Checking')", timeout: 30), status.label)
        print("MAP_SMOKE_STATUS \(status.label)")
    }

    // MARK: Review B-9: a long-press proposes; Plan here / Cancel / Undo

    @MainActor
    func testLongPressProposesAndUndoRestores() {
        let app = openMap(place: Self.camp, extra: ["-MapCamera", "38.374,-109.9654,10"])
        let place = app.staticTexts["map.placeLabel"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        let original = place.label
        XCTAssertTrue(original.contains("38.3740, -109.9654"), original)
        let map = app.otherElements["map.view"]
        sleep(2)

        // Long-press, Cancel: nothing changes.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(forDuration: 1.0)
        XCTAssertTrue(el(app, "map.candidate").waitForExistence(timeout: 5), "no Plan here bar")
        XCTAssertTrue(el(app, "map.candidatePin").exists, "no candidate pin")
        attach(app, "candidate-bar")
        XCTAssertEqual(place.label, original, "a long-press changed the place")
        app.buttons["map.candidate.cancel"].tap()
        XCTAssertFalse(el(app, "map.candidate").waitForExistence(timeout: 1))
        XCTAssertEqual(place.label, original)

        // Long-press, Plan here: the place changes, with Undo offered.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["map.candidate.confirm"].waitForExistence(timeout: 5))
        app.buttons["map.candidate.confirm"].tap()
        XCTAssertTrue(waitLabel(place, "label != %@", original), "Plan here did not change the place")
        let moved = place.label
        XCTAssertFalse(moved.contains("38.3740, -109.9654"), moved)
        let undo = app.buttons["map.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo")
        XCTAssertTrue(el(app, "map.undoBar").label.contains("Planning for this pin") || app.staticTexts["Planning for this pin"].exists)
        attach(app, "undo-bar")

        // Undo: the place comes back.
        undo.tap()
        XCTAssertTrue(waitLabel(place, "label == %@", original), "Undo did not restore: \(place.label)")
    }

    /// Product review §4: a planned pin is the remembered place after a relaunch.
    @MainActor
    func testPlannedPinSurvivesRelaunch() {
        var app = openMap(extra: ["-MapCamera", "38.374,-109.9654,10", "-resetRememberedPlace"], persist: true)
        sleep(2)
        app.otherElements["map.view"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["map.candidate.confirm"].waitForExistence(timeout: 5))
        let proposed = app.staticTexts["map.candidate.coordinates"].label
        app.buttons["map.candidate.confirm"].tap()
        let place = app.staticTexts["map.placeLabel"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        XCTAssertTrue(place.label.contains(proposed), "\(place.label) vs \(proposed)")
        app.terminate()

        app = openMap(extra: ["-MapCamera", "38.374,-109.9654,10"], persist: true)
        let again = app.staticTexts["map.placeLabel"]
        XCTAssertTrue(again.waitForExistence(timeout: 10), "no place after relaunch")
        XCTAssertTrue(again.label.contains(proposed), "relaunch opened on \(again.label), expected \(proposed)")
        app.terminate()
        // Leave nothing behind for the next test.
        app = openMap(extra: ["-resetRememberedPlace"], persist: true)
        app.terminate()
    }

    // MARK: Centre on the pin (bottom right, beside centre on me)

    @MainActor
    func testCenterOnPinRecentres() {
        let app = openMap(place: Self.camp, extra: ["-MapCamera", "38.374,-109.9654,10"])
        let center = el(app, "map.center")
        XCTAssertTrue(waitLabel(center, "label BEGINSWITH '38.37'"), center.label)
        let map = app.otherElements["map.view"]
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)))
        sleep(2)
        XCTAssertFalse(center.label.hasPrefix("38.37"), "pan did not move: \(center.label)")
        let button = app.buttons["map.centerPin"]
        XCTAssertTrue(button.isHittable)
        // One-handed: bottom right of the screen.
        XCTAssertGreaterThan(button.frame.midX, app.frame.width * 0.75)
        XCTAssertGreaterThan(button.frame.midY, app.frame.height * 0.5)
        button.tap()
        XCTAssertTrue(waitLabel(center, "label BEGINSWITH '38.37' AND label CONTAINS '-109.96'"), "not recentred: \(center.label)")
    }

    // MARK: Review B-6: the map fills the tab; labels never overlap

    /// Default and Accessibility L text, standard and field: with the sheet
    /// collapsed, the map shows above the sheet on at least 70 % of the screen.
    @MainActor
    func testCollapsedSheetLeavesTheMapMostOfTheScreen() {
        for size in ["", "UICTContentSizeCategoryAccessibilityL"] {
            for field in [false, true] {
                let extra = size.isEmpty ? [] : ["-UIPreferredContentSizeCategoryName", size]
                let app = openMap(place: Self.camp, field: field, extra: extra + ["-MapCamera", "38.374,-109.9654,8"])
                let sheet = app.otherElements["map.sheet"]
                XCTAssertTrue(sheet.waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["map.placeLabel"].waitForExistence(timeout: 10))
                sleep(5)
                let screen = app.frame.height
                let share = sheet.frame.minY / screen
                let name = "map-\(size.isEmpty ? "default" : "axL")-\(field ? "field" : "std")"
                print(String(format: "MAP_SHARE %@ sheet top %.0f of %.0f pt: map %.1f %%", name, sheet.frame.minY, screen, share * 100))
                attach(app, name)
                XCTAssertGreaterThanOrEqual(share, 0.70, "\(name): map only \(share)")
                // The peek: place, basemap, the target line.
                XCTAssertTrue(el(app, "map.peekBasemap").exists)
                XCTAssertTrue(el(app, "map.peekSummary").exists)
                app.terminate()
            }
        }
    }

    /// Compare view at z8 at Candlestick: line labels overlap nothing.
    @MainActor
    func testLabelsNeverOverlapAtZoom8() {
        let app = openMap(place: Self.camp, extra: ["-MapCamera", "38.374,-109.9654,8"])
        let compare = el(app, "map.compare")
        reveal(app, compare)
        compare.tap()
        let summary = el(app, "map.lineSummary")
        XCTAssertTrue(waitLabel(summary, "label CONTAINS 'Sun set'"))
        let lines = summary.label.components(separatedBy: "; ").count
        sheet(app, "collapsed")
        sleep(6)
        attach(app, "labels-z8-compare")
        // The declutter's own record of what it drew (MapLibre keeps exposing
        // hidden annotation views to accessibility, so their frames can't be used).
        let readout = el(app, "map.labelFrames")
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        let frames: [CGRect] = readout.label.split(separator: ";").compactMap { part in
            let n = part.split(separator: ",").compactMap { Double($0) }
            return n.count == 4 ? CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) : nil
        }
        print("MAP_LABELS shown \(frames.count) of \(lines) lines: \(readout.label)")
        XCTAssertGreaterThanOrEqual(frames.count, 3, "too few labels shown")
        var reserved: [(String, CGRect)] = [("sheet", app.otherElements["map.sheet"].frame)]
        for id in ["map.basemapButton", "map.pinMe", "map.centerPin", "map.locate", "map.pin", "map.attribution"] {
            let e = el(app, id)
            if e.exists { reserved.append((id, e.frame)) }
        }
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b), "labels overlap: \(a) \(b)") }
            for (id, r) in reserved { XCTAssertFalse(a.intersects(r), "label \(a) covers \(id) \(r)") }
        }
        if frames.count < lines {
            sheet(app, "full height")
            XCTAssertTrue(el(app, "map.hiddenLabels").waitForExistence(timeout: 5), "hidden labels not noted in the sheet")
        }
    }

    /// The published layers are on the phone after the first load (the
    /// fixture archives are a few KB, so this downloads almost nothing).
    @MainActor
    func testPublishedLayersKeptOffline() {
        let app = openMap()
        let lp = app.staticTexts["offline.lightPollution"]
        reveal(app, lp)
        let saved = NSPredicate(format: "label BEGINSWITH 'On this phone'")
        for id in ["offline.lightPollution", "offline.land", "offline.places"] {
            let e = app.staticTexts[id]
            let x = XCTNSPredicateExpectation(predicate: saved, object: e)
            XCTAssertEqual(XCTWaiter().wait(for: [x], timeout: 60), .completed, "\(id): \(e.label)")
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        // TEST_RUNNER_MAP_SHOTS=/folder also writes the PNGs there.
        if let dir = ProcessInfo.processInfo.environment["MAP_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
    }
}
