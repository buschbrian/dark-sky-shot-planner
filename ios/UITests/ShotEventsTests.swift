import XCTest

/// Review B-3 and the product review of 2026-09-27: the shot window is
/// Tonight's main answer (with a saved spot's skyline), a moon-limited night
/// reads the same on Tonight, Week and Spots, and sky events reach Tonight and
/// Week and can become the plan. Offline UI-test mode throughout.
final class ShotEventsTests: XCTestCase {
    static let camp = (lat: "38.374031", lon: "-109.965416")
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(env: [String: String] = [:], resetSpots: Bool = false) {
        app.launchEnvironment = env
        app.launchArguments = ["-DarkSkyUITest", "-FieldMode", "NO"] + (resetSpots ? ["-resetSpots"] : [])
        app.launch()
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func waitFor(_ e: XCUIElement, labelContains text: String, timeout: TimeInterval = 20) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    /// Types a place (or a web share link) into Tonight's location sheet.
    private func enterLocation(_ text: String) {
        let choose = app.buttons["tonight.chooseLocation"]
        (choose.waitForExistence(timeout: 10) ? choose : app.buttons["tonight.location"]).tap()
        let field = el("location.input")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["location.use"].tap()
        XCTAssertTrue(el("tonight.headline").waitForExistence(timeout: 15))
    }

    private func addSpot(name: String, lat: String, lon: String) {
        app.tabBars.buttons["Spots"].tap()
        let first = app.buttons["add-first-spot"]
        (first.waitForExistence(timeout: 5) ? first : app.buttons["add-spot"]).tap()
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

    /// B-3: at Candlestick with the measured skyline, on a new-moon May night
    /// when the core rises after midnight, Tonight's first block names the
    /// clearance time and the usable minutes against the saved skyline, and
    /// its actions save the plan and find the core in Sky.
    @MainActor
    func testShotWindowAtCandlestickNamesClearanceAndMinutes() {
        launch(resetSpots: true)
        addSpot(name: "Candlestick Camp", lat: Self.camp.lat, lon: Self.camp.lon)
        app.buttons["spot-row-Candlestick Camp"].tap()
        let measured = app.buttons["horizon-measured"]
        measured.swipeUpUntilVisible(in: app)
        measured.tap()
        XCTAssertTrue(el("skyline-chart").waitForExistence(timeout: 10))
        app.swipeDown()
        // The compact line under the spot's week strip.
        let line = el("spot.shotLine")
        line.swipeUpUntilVisible(in: app)
        XCTAssertTrue(waitFor(line, labelContains: "Galactic Core"), line.label)

        app.tabBars.buttons["Tonight"].tap()
        enterLocation("https://example.github.io/#lat=\(Self.camp.lat)&lon=\(Self.camp.lon)&date=2027-05-06")
        let headline = el("shot.headline")
        XCTAssertTrue(waitFor(headline, labelContains: "clears the ridge"), headline.label)
        XCTAssertTrue(headline.label.contains("min moon-free"), headline.label)
        XCTAssertNotNil(headline.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression), "a clearance time: \(headline.label)")
        XCTAssertTrue(el("shot.window").label.hasPrefix("Usable "), el("shot.window").label)
        XCTAssertTrue(el("shot.clearance").label.contains("saved skyline"), el("shot.clearance").label)
        // Answer first: the shot plan sits above the moon-free darkness card.
        XCTAssertLessThan(el("shot.target").frame.minY, el("tonight.headline").frame.minY)

        let save = el("shot.save")
        save.swipeUpUntilVisible(in: app)
        save.tap()
        XCTAssertTrue(el("shot.savedNote").waitForExistence(timeout: 5))

        el("shot.findInSky").tap()
        let preview = el("sky.planPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 20), "Sky previews the plan")
        XCTAssertTrue(preview.label.contains("Galactic Core"), preview.label)
        XCTAssertTrue(waitFor(el("sky.find.guidance"), labelContains: "Galactic Center"))
    }

    /// Product review §2: the full-moon night of 2026-09-26 is "Moon up" on
    /// Tonight (both blocks), Week and Spots, worded for the activity, and
    /// "Find the next suitable night" leaves it for a night with a window.
    @MainActor
    func testFullMoonNightReadsTheSameEverywhere() {
        launch(env: ["DS_FIRST_NIGHT": "2026-09-26"], resetSpots: true)
        addSpot(name: "Flat Test", lat: "38.35", lon: "-109.95")
        app.buttons["spot-row-Flat Test"].tap()
        let spotVerdict = el("night-verdict")
        XCTAssertTrue(spotVerdict.waitForExistence(timeout: 30))
        XCTAssertTrue(waitFor(spotVerdict, labelContains: "Moon up"), "Spots: \(spotVerdict.label)")

        app.tabBars.buttons["Tonight"].tap()
        enterLocation("https://example.github.io/#lat=38.35&lon=-109.95&date=2026-09-26")
        XCTAssertTrue(waitFor(el("tonight.verdict"), labelContains: "Moon up"), "Tonight night: \(el("tonight.verdict").label)")
        XCTAssertFalse(el("tonight.verdict").label.contains("No-go"), el("tonight.verdict").label)
        XCTAssertTrue(waitFor(el("shot.verdict"), labelContains: "Moon up"), "Tonight shot: \(el("shot.verdict").label)")
        XCTAssertTrue(el("shot.headline").label.contains("No moon-free Milky Way window"), el("shot.headline").label)

        el("tonight.factors").tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'no weather can change that tonight'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "activity-scoped wording in the factor sheet")
        el("factors.done").tap()

        app.segmentedControls.buttons["Week"].tap()
        let row = app.buttons["week.row.2026-09-26"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(row.label.contains("Moon up"), "Week: \(row.label)")
        app.segmentedControls.buttons["Tonight"].tap()

        let date = el("tonight.date")
        let before = date.label
        el("shot.findNext").tap()
        let moved = NSPredicate(format: "label != %@", before)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: moved, object: date)], timeout: 20), .completed)
        XCTAssertTrue(waitFor(el("shot.window"), labelContains: "Usable"), "the next night has a window")
    }

    /// Events: Tonight's section and a Week badge on a night with a known
    /// event (Jupiter at opposition, night of 2027-02-10 at Canyonlands,
    /// `shared/golden/sky-events.json` case canyonlands-2027-02-01), and
    /// "Plan this" makes Jupiter the shot target for that night.
    @MainActor
    func testEventsSectionAndWeekBadgeOnAnEventNight() {
        launch(env: ["DS_FIRST_NIGHT": "2027-02-08"])
        enterLocation("https://example.github.io/#lat=\(Self.camp.lat)&lon=\(Self.camp.lon)&date=2027-02-10")
        let section = el("skyEvents.section")
        section.swipeUpUntilVisible(in: app)
        XCTAssertTrue(section.exists)
        let jupiter = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'skyEvents.row' AND label CONTAINS 'Jupiter at opposition'")).firstMatch
        XCTAssertTrue(jupiter.waitForExistence(timeout: 10), "the opposition is in Tonight's section")

        let plan = app.buttons.matching(NSPredicate(format: "identifier == 'skyEvents.plan' AND label CONTAINS 'Jupiter'")).firstMatch
        plan.swipeUpUntilVisible(in: app)
        plan.tap()
        XCTAssertTrue(waitFor(el("shot.target"), labelContains: "Jupiter"), el("shot.target").label)

        app.segmentedControls.buttons["Week"].tap()
        let badge = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'skyEvents.badge' AND label CONTAINS 'Jupiter at opposition'")).firstMatch
        badge.swipeUpUntilVisible(in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "a Week row carries the event badge")
    }
}
