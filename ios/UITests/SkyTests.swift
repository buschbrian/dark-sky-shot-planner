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
        // Start in the standard palette: field mode now survives relaunch and
        // replaces the system tab bar with the red dock.
        app.launchArguments += ["-DarkSkyUITest", "-FieldMode", "NO"] + arguments
        app.launch()
        // A later "-FieldMode YES" wins: field mode has the red dock, not the tab bar.
        if let i = arguments.lastIndex(of: "-FieldMode"), arguments.indices.contains(i + 1), arguments[i + 1] == "YES" {
            app.buttons["fieldDock.sky"].tap()
        } else {
            app.tabBars.buttons["Sky"].tap()
        }
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

    // MARK: - Compass and gyroscope calibration

    /// A low magnetometer (Core Motion's own calibration state) brings up the
    /// palette-drawn figure-8 guide instead of iOS's white prompt.
    @MainActor
    func testLowMagnetometerShowsFigureEightGuide() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z", "-SkyDemoMagneticAccuracy", "low"])
        let guide = element(app, "sky.figure8")
        XCTAssertTrue(guide.waitForExistence(timeout: 15))
        XCTAssertTrue(guide.label.contains("Magnetometer low"), guide.label)
        XCTAssertTrue(element(app, "sky.heading").label.contains("magnetometer low"))
        attachScreenshot("sky-figure8-normal")
        element(app, "sky.fieldMode").tap()
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        attachScreenshot("sky-figure8-field")
        element(app, "sky.figure8.hide").tap()
        XCTAssertFalse(element(app, "sky.figure8").exists)
    }

    @MainActor
    func testGoodMagnetometerHasNoGuide() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z", "-SkyDemoMagneticAccuracy", "high"])
        XCTAssertTrue(element(app, "sky.overlay").waitForExistence(timeout: 15))
        XCTAssertFalse(element(app, "sky.figure8").exists)
    }

    /// Two stars fix heading and tilt; the badge reports the residual.
    @MainActor
    func testTwoStarCalibrationReportsResidual() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z", "-SkyDemoHeadingAccuracy", "25"])
        XCTAssertTrue(summary(app).contains("approximate"))
        element(app, "sky.calibrate").tap()
        app.buttons["Vega"].firstMatch.tap()
        element(app, "sky.calibration.add").tap()
        XCTAssertTrue(element(app, "sky.calibration.status").label.contains("Added: Vega"))
        app.buttons["Antares"].firstMatch.tap()
        element(app, "sky.calibration.add").tap()
        attachScreenshot("sky-calibration-two-points")
        element(app, "sky.calibration.align").tap()
        let heading = element(app, "sky.heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.label.contains("calibrated on Vega, Antares"), heading.label)
        XCTAssertTrue(heading.label.contains("residual 0.00°"), heading.label)
        XCTAssertFalse(summary(app).contains("approximate"))
    }

    /// Alignments that disagree by more than the config bound are refused.
    @MainActor
    func testDisagreeingAlignmentsAreRejected() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z", "-SkyDemoAlignmentError", "3"])
        element(app, "sky.calibrate").tap()
        app.buttons["Vega"].firstMatch.tap()
        element(app, "sky.calibration.add").tap()
        app.buttons["Altair"].firstMatch.tap()
        element(app, "sky.calibration.add").tap()
        element(app, "sky.calibration.align").tap()
        let rejected = element(app, "sky.calibration.rejected")
        XCTAssertTrue(rejected.waitForExistence(timeout: 5))
        XCTAssertTrue(rejected.label.contains("Refused"), rejected.label)
        attachScreenshot("sky-calibration-rejected")
        XCTAssertFalse(element(app, "sky.heading").label.contains("calibrated on"))
    }

    /// A magnetic disturbance keeps the overlay approximate until recalibrated.
    @MainActor
    func testMagneticDisturbanceNeedsRecalibration() {
        let app = openSky(["-SkyDemoTime", "2026-09-27T04:00:00Z", "-SkyDemoDisturbance", "YES"])
        XCTAssertTrue(summary(app).contains("approximate"))
        let note = element(app, "sky.approximate")
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("Magnetic disturbance"), note.label)
        attachScreenshot("sky-disturbance")
        element(app, "sky.calibrate").tap()
        app.buttons["Moon"].firstMatch.tap()
        element(app, "sky.calibration.align").tap()
        XCTAssertTrue(element(app, "sky.heading").waitForExistence(timeout: 5))
        XCTAssertFalse(summary(app).contains("approximate"))
        XCTAssertFalse(element(app, "sky.approximate").exists)
    }

    @MainActor
    func testSensorDiagnosticsPanel() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z", "-SkySensorDiagnostics", "YES", "-SkyDemoMagneticAccuracy", "medium"])
        let diag = element(app, "sky.diagnostics")
        XCTAssertTrue(diag.waitForExistence(timeout: 15))
        XCTAssertTrue(diag.label.contains("magAcc=medium"), diag.label)
        XCTAssertTrue(diag.label.contains("headingAcc="), diag.label)
    }

    // MARK: - Realism: find, trails, simulated sky

    @MainActor
    func testFindConstellationGuidesAndCentres() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z"])
        XCTAssertTrue(element(app, "sky.overlay").waitForExistence(timeout: 15))
        element(app, "sky.find").tap()
        let cygnus = element(app, "sky.find.item.Cygnus")
        XCTAssertTrue(cygnus.waitForExistence(timeout: 5))
        cygnus.tap()
        let guidance = element(app, "sky.find.guidance")
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        XCTAssertTrue(guidance.label.hasPrefix("Cygnus:"), guidance.label)
        XCTAssertTrue(guidance.label.contains("turn") || guidance.label.contains("tilt"), guidance.label)
        XCTAssertTrue(summary(app).contains("Finding Cygnus"))
        attachScreenshot("sky-find-arrow")
        element(app, "sky.find.point").tap()
        let centred = NSPredicate(format: "label CONTAINS 'centred'")
        expectation(for: centred, evaluatedWith: guidance)
        waitForExpectations(timeout: 5)
        let text = summary(app)
        XCTAssertTrue(text.contains("Constellations on screen:") && text.contains("Cygnus"), text)
        XCTAssertTrue(text.contains("Bright stars on screen:") && text.contains("Deneb"), text)
        attachScreenshot("sky-find-centred")
    }

    @MainActor
    func testStarTrailDesigner() {
        let app = openSky(["-SkyDemoTime", "2026-07-15T05:00:00Z"])
        XCTAssertTrue(element(app, "sky.overlay").waitForExistence(timeout: 15))
        element(app, "sky.trails").tap()
        element(app, "sky.trails.duration.120").tap()
        let readout = element(app, "sky.trails.readout")
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        let arcs = NSPredicate(format: "label CONTAINS 'Arcs 30.1°'")
        expectation(for: arcs, evaluatedWith: readout)
        waitForExpectations(timeout: 5)
        element(app, "sky.trails.pointPole").tap()
        let pole = NSPredicate(format: "label CONTAINS 'Pole in frame: 50% across, 33% down'")
        expectation(for: pole, evaluatedWith: readout)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(readout.label.contains("Polaris 0.6"), readout.label)
        XCTAssertTrue(summary(app).contains("Star trails over 2 h 00 min: arcs of 30°"))
        attachScreenshot("sky-trails-pole")
        element(app, "sky.fieldMode").tap()
        XCTAssertTrue(element(app, "sky.overlay").waitForExistence(timeout: 5))
        attachScreenshot("sky-trails-pole-field")
    }

    @MainActor
    func testMeteorRadiantFromProvider() {
        let app = openSky(["-SkyDemoTime", "2026-08-13T09:00:00Z", "-SkyDemoRadiants", "YES", "-SkyDemoLook", "45,45,90"])
        let text = summary(app)
        XCTAssertTrue(text.contains("Perseids (demo) radiant"), text)
        XCTAssertTrue(text.contains("meteors an hour"), text)
        attachScreenshot("sky-radiant")
    }

    /// The simulated sky at dusk (facing the western glow), full dark
    /// (Milky Way core) and under a full Moon, in both palettes.
    @MainActor
    func testSimulatedSkyScreenshots() {
        let scenes: [(String, String, String)] = [
            ("dusk", "2026-07-15T03:15:00Z", "295,15,90"),
            ("dark", "2026-07-15T05:00:00Z", "180,25,90"),
            ("moonlit", "2026-09-27T04:00:00Z", "110,25,90"),
        ]
        for (name, time, look) in scenes {
            for field in [false, true] {
                var args = ["-SkyDemoTime", time, "-SkyDemoLook", look]
                if field { args += ["-FieldMode", "YES"] }
                let app = openSky(args)
                XCTAssertTrue(element(app, "sky.overlay").waitForExistence(timeout: 15))
                attachScreenshot("sky-sim-\(name)-\(field ? "field" : "normal")")
                app.terminate()
            }
        }
    }
}
