import CoreGraphics
import UIKit
import XCTest

/// Map engine: basemaps, the location puck, offline areas. Camera positions
/// come from `-MapCamera "lat,lon,zoom"`, never from gestures, so the
/// screenshots are repeatable. Candlestick Camp is 38.3740, −109.9654.
///
/// Opt-in: these need live USGS/AWS tiles and a simulated location, so the
/// default suite skips them. Run with
/// `xcrun simctl location <sim> set 38.3740,-109.9654` and
/// `TEST_RUNNER_MAP_ENGINE=1 xcodebuild test … -only-testing:DarkSkyUITests/MapEngineTests`.
final class MapEngineTests: XCTestCase {
    static let candlestick = "38.3740,-109.9654"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MAP_ENGINE"] == "1",
                          "network + simulated location: set TEST_RUNNER_MAP_ENGINE=1")
    }

    @MainActor
    private func openMap(zoom: Double = 12, extra: [String] = [], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-resetMapState"] : []) + ["-MapCamera", "\(Self.candlestick),\(zoom)"] + extra
        app.launch()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.otherElements["map.view"].waitForExistence(timeout: 15), "map view missing")
        return app
    }

    @MainActor
    @discardableResult
    private func waitRendered(_ app: XCUIApplication, timeout: TimeInterval = 30) -> String {
        let e = app.descendants(matching: .any)["map.timing"]
        let done = NSPredicate(format: "label CONTAINS 'fully rendered' AND NOT (label CONTAINS 'pending')")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: done, object: e)], timeout: timeout), .completed,
                       "map never fully rendered: \(e.label)")
        return e.label
    }

    /// Selects a basemap with the on-map chooser.
    @MainActor
    private func choose(_ app: XCUIApplication, _ id: String) {
        app.buttons["map.basemapButton"].tap()
        let b = app.buttons["map.basemap.\(id)"]
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        b.tap()
    }

    @MainActor
    func testBasemapSwitchShowsTilesAndCredit() throws {
        let app = openMap(zoom: 12)
        print("MAP_TIMING basemap topo: \(waitRendered(app))")
        let credit = app.staticTexts["map.attribution"]
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        XCTAssertTrue(credit.label.contains("USGS"), credit.label)
        sleep(3)
        let topo = try mapStats(app)
        attach(app, "basemap-topo-z12")
        XCTAssertGreaterThan(topo.stddev, 12, "topo looks blank: \(topo)")

        choose(app, "imagery")
        XCTAssertTrue(credit.label.contains("imagery"), credit.label)
        sleep(5)
        let imagery = try mapStats(app)
        attach(app, "basemap-imagery-z12")
        XCTAssertGreaterThan(imagery.stddev, 12, "imagery looks blank: \(imagery)")
        XCTAssertNotEqual(topo.mean, imagery.mean, accuracy: 3, "switch changed nothing")

        choose(app, "darkRelief")
        XCTAssertTrue(credit.label.contains("terrain"), credit.label)
        sleep(5)
        let dark = try mapStats(app)
        attach(app, "basemap-dark-z12")
        XCTAssertLessThan(dark.mean, topo.mean - 60, "dark relief not dark: \(dark) vs \(topo)")
        XCTAssertGreaterThan(dark.stddev, 8, "dark relief looks blank: \(dark)")

        // The panel shows the same choice (the map is never the only way).
        let panelChoice = app.buttons["basemap.darkRelief"]
        for _ in 0..<6 where !panelChoice.isHittable { scrollPanel(app) }
        XCTAssertTrue(panelChoice.isSelected)
        app.buttons["basemap.topo"].tap()
        XCTAssertTrue(app.buttons["basemap.topo"].isSelected)
        XCTAssertEqual(credit.label, "USGS The National Map")
    }

    /// Closer in: trails, tracks and names at Candlestick Camp.
    @MainActor
    func testBasemapsAtZoom15() throws {
        let app = openMap(zoom: 15)
        waitRendered(app)
        for (id, name) in [("topo", "basemap-topo-z15"), ("imagery", "basemap-imagery-z15"), ("darkRelief", "basemap-dark-z15")] {
            if id != "topo" { choose(app, id) }
            sleep(5)
            let s = try mapStats(app)
            print("Z15 \(id) \(s)")
            XCTAssertGreaterThan(s.stddev, 8, "\(id) blank at z15: \(s)")
            attach(app, name)
        }
    }

    /// Field mode: Dark relief is its default, drawn only in red and dim.
    @MainActor
    func testFieldModeDarkReliefIsRedAndDim() throws {
        let app = openMap(zoom: 13, extra: ["-FieldMode", "YES"])
        waitRendered(app)
        XCTAssertTrue(app.staticTexts["map.attribution"].label.contains("terrain"))
        sleep(5)
        let s = try mapStats(app)
        attach(app, "field-dark-z13")
        print("FIELD_SCAN \(s)")
        // Whole map frame, including the panel's own age badge and hint (MapScreen).
        print("FIELD_SCAN_WHOLE_MAP \(try mapStats(app, wholeMap: true))")
        XCTAssertLessThanOrEqual(s.maxGB, 12, "green/blue light in field mode: \(s)")
        XCTAssertLessThan(s.p999Red, 160, "field map too bright: \(s)")
        XCTAssertGreaterThan(s.stddev, 2, "field map blank: \(s)")
    }

    @MainActor
    func testLocationPuckCentersAndPins() throws {
        let app = openMap(zoom: 9)
        waitRendered(app)
        let monitor = addUIInterruptionMonitor(withDescription: "location") { alert in
            for label in ["Allow While Using App", "Allow Once"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.buttons["map.locate"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        let user = app.descendants(matching: .any)["map.userLocation"]
        let onScreen = NSPredicate(format: "label BEGINSWITH 'puck on screen'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: onScreen, object: user)], timeout: 20), .completed,
                       "puck not on screen: \(user.label)")
        XCTAssertTrue(user.label.contains("38.374"), user.label)
        let center = app.descendants(matching: .any)["map.center"]
        let near = NSPredicate(format: "label BEGINSWITH '38.37'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: near, object: center)], timeout: 10), .completed,
                       "not centred on the fix: \(center.label)")
        attach(app, "location-puck-follow")

        // Pan away, then centre again.
        let map = app.otherElements["map.view"]
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)))
        sleep(2)
        XCTAssertFalse(center.label.hasPrefix("38.374"), "pan did not move: \(center.label)")
        app.buttons["map.locate"].tap()
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: near, object: center)], timeout: 10), .completed,
                       "re-centre failed: \(center.label)")

        app.buttons["map.pinMe"].tap()
        let place = app.staticTexts["map.placeLabel"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        XCTAssertTrue(place.label.contains("38.3740, -109.9654"), place.label)
        sleep(2)
        attach(app, "location-pin-me")
    }

    /// Downloads a small area around Candlestick, relaunches with the map's
    /// network cut and its cache emptied, and checks the basemap still draws.
    @MainActor
    func testOfflineAreaRendersWithoutNetwork() throws {
        var app = openMap(zoom: 13)
        waitRendered(app)
        deleteAllAreas(app)
        let estimate = app.staticTexts["offline.view.estimate"]
        for _ in 0..<10 where !(estimate.exists && estimate.isHittable) { scrollPanel(app) }
        XCTAssertTrue(estimate.exists, "no estimate row")
        print("OFFLINE_ESTIMATE \(estimate.label)")
        let mb = Self.megabytes(in: estimate.label)
        XCTAssertNotNil(mb, estimate.label)
        XCTAssertLessThan(mb ?? 99, 20, "test area too big: \(estimate.label)")
        app.buttons["offline.keepView"].tap()
        let status = app.staticTexts["offline.area.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "no download row")
        let saved = NSPredicate(format: "label BEGINSWITH 'Saved'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: saved, object: status)], timeout: 180), .completed,
                       "download did not finish: \(status.label)")
        print("OFFLINE_SAVED \(status.label)")
        app.terminate()

        app = openMap(zoom: 13, extra: ["-DarkSkyOffline", "-clearMapAmbientCache"], reset: false)
        // Offline, MapLibre keeps retrying tiles it can't reach (lower-zoom
        // prefetches outside the pack), so "fully rendered" never comes: wait for
        // the first frame, then give the pack's tiles time to draw.
        let timing = app.descendants(matching: .any)["map.timing"]
        let first = NSPredicate(format: "label BEGINSWITH 'first frame'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: first, object: timing)], timeout: 20), .completed)
        print("OFFLINE_TIMING \(timing.label)")
        sleep(8)
        let s = try mapStats(app)
        attach(app, "offline-topo-z13")
        print("OFFLINE_RENDER \(s)")
        XCTAssertGreaterThan(s.stddev, 12, "offline basemap blank: \(s)")
        XCTAssertGreaterThan(s.mean, 120, "offline topo should be light paper, got \(s)")

        deleteAllAreas(app)
        XCTAssertFalse(app.staticTexts["offline.area.status"].exists, "area not deleted")
    }

    // MARK: Helpers

    @MainActor
    private func deleteAllAreas(_ app: XCUIApplication) {
        let del = app.buttons["offline.delete"]
        for _ in 0..<10 where !(app.staticTexts["offline.view.estimate"].exists && app.staticTexts["offline.view.estimate"].isHittable) {
            scrollPanel(app)
        }
        var n = 0
        while del.exists, n < 10 {
            if !del.isHittable { scrollPanel(app) }
            del.tap()
            sleep(2)
            n += 1
        }
    }

    static func megabytes(in text: String) -> Double? {
        guard let m = text.firstMatch(of: /About ([\d.,]+) (KB|MB|GB)/) else { return nil }
        let v = Double(m.1.replacingOccurrences(of: ",", with: "")) ?? 0
        switch m.2 {
        case "KB": return v / 1000
        case "GB": return v * 1000
        default: return v
        }
    }

    struct Stats: CustomStringConvertible {
        var mean: Double, stddev: Double, maxGB: Int, maxRed: Int, p999Red: Int
        var description: String {
            String(format: "mean %.1f sd %.1f maxGB %d maxR %d p99.9R %d", mean, stddev, maxGB, maxRed, p999Red)
        }
    }

    /// Luma statistics over the map, inset past its corner badges and buttons.
    @MainActor
    private func mapStats(_ app: XCUIApplication, wholeMap: Bool = false) throws -> Stats {
        let shot = XCUIScreen.main.screenshot()
        let cg = try XCTUnwrap(shot.image.cgImage)
        let scale = CGFloat(cg.width) / shot.image.size.width
        let f = app.otherElements["map.view"].frame
        // The middle of the map: clear of the age badge, hint, credit and buttons.
        let r = wholeMap ? f : CGRect(x: f.minX + 20, y: f.minY + 70, width: f.width - 100, height: f.height - 150)
        let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
        let w = Int(px.width), h = Int(px.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(try XCTUnwrap(cg.cropping(to: px)), in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0, sq = 0.0, maxGB = 0, maxR = 0
        var reds = [Int](repeating: 0, count: 256)
        for i in stride(from: 0, to: buf.count, by: 4) {
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
            let y = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            sum += y
            sq += y * y
            maxGB = max(maxGB, g, b)
            maxR = max(maxR, r)
            reds[r] += 1
        }
        let n = Double(w * h)
        let mean = sum / n
        var acc = 0, p999 = 255
        for v in stride(from: 255, through: 0, by: -1) {
            acc += reds[v]
            if Double(acc) > n * 0.001 { p999 = v; break }
        }
        return Stats(mean: mean, stddev: (sq / n - mean * mean).squareRoot(), maxGB: maxGB, maxRed: maxR, p999Red: p999)
    }

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
