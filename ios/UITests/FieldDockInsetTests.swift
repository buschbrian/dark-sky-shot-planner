import XCTest

/// Field mode hides the system tab bar and shows `FieldDock` in its place.
/// The dock must be real bottom space for every screen, pushed ones included:
/// scrolled to the bottom, each screen's last control ends at or above the
/// dock's top edge and takes a tap. Runs at the default text size and at
/// Accessibility L, where the dock's labels also stay on one line and the
/// dock stays under 18 % of the screen. Written for the iPhone 17 (874 pt),
/// the shortest current iPhone, where the old per-tab inset failed.
final class FieldDockInsetTests: XCTestCase {
    enum Size: String, CaseIterable {
        case std, axl

        var arguments: [String] {
            switch self {
            case .std: []
            case .axl: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
            }
        }
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(_ size: Size, tab: String? = nil, field: Bool = true, extra: [String] = [],
                        env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["DS_PLACE": DesignTourTests.place, "DS_FIXTURE_CONDITIONS": "1"].merging(env) { $1 }
        app.launchArguments = ["-DarkSkyUITest", "-FieldMode", field ? "YES" : "NO"]
            + (tab.map { ["-DSTab", $0] } ?? []) + size.arguments + extra
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    // MARK: Screens

    @MainActor
    func testToolsListLastRowClearsTheDock() throws {
        for size in Size.allCases {
            let app = launch(size, tab: "tools")
            XCTAssertTrue(app.buttons["tools.capture"].waitForExistence(timeout: 15))
            scrollToBottom(app)
            let about = app.buttons["tools.about"]
            try assertClearOfDock(app, "tools-\(size)", last: about)
            try shot(app, "dock-tools-\(size)")
            app.terminate()
        }
    }

    @MainActor
    func testPushedNPFCalculatorClearsTheDock() throws {
        ensureGear()
        for size in Size.allCases {
            let app = launch(size, tab: "tools")
            let calc = app.buttons["tools.calc.starExposure"]
            XCTAssertTrue(calc.waitForExistence(timeout: 15))
            calc.swipeUpUntilVisible(in: app)
            calc.tap()
            XCTAssertTrue(el(app, "tools.result.npf").waitForExistence(timeout: 5))
            scrollToBottom(app)
            try assertClearOfDock(app, "npf-\(size)")
            // The last line on the page (the gear provenance) is not under the dock either.
            let chip = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'your gear profile'")).firstMatch
            XCTAssertTrue(chip.exists, "npf-\(size): provenance line")
            XCTAssertLessThanOrEqual(chip.frame.maxY, dockTop(app) + 0.5, "npf-\(size): the last line ends above the dock")
            try shot(app, "dock-npf-\(size)")
            app.terminate()
        }
    }

    @MainActor
    func testCaptureBarClearsTheDock() throws {
        for size in Size.allCases {
            let app = launch(size, tab: "tools", extra: ["-CaptureDemo", "setup", "-capture.guideSeen", "YES"])
            let row = app.buttons["tools.capture"]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.swipeUpUntilVisible(in: app)
            try assertClearOfDock(app, "capture-row-\(size)", last: row)
            row.tap()
            let start = app.buttons["capture.start"]
            XCTAssertTrue(start.waitForExistence(timeout: 10), "\(size): the Capture screen opens from Tools")
            try assertClearOfDock(app, "capture-\(size)", last: start)
            let bar = el(app, "capture.bar")
            XCTAssertTrue(bar.exists)
            XCTAssertLessThanOrEqual(bar.frame.maxY, dockTop(app) + 0.5, "capture-\(size): the whole bar sits above the dock")
            // The bar sits right on the dock: no hand-tuned gap left between them.
            XCTAssertLessThanOrEqual(dockTop(app) - bar.frame.maxY, 1, "capture-\(size): no gap between bar and dock")
            try shot(app, "dock-capture-\(size)")
            app.terminate()
        }
    }

    @MainActor
    func testSpotsListClearsTheDock() throws {
        for size in Size.allCases {
            let app = launch(size, tab: "spots", extra: ["-resetSpots", "-seedSpots", "9"])
            XCTAssertTrue(app.buttons["spot-row-Seeded spot 1"].waitForExistence(timeout: 15))
            scrollToBottom(app)
            try assertClearOfDock(app, "spots-\(size)", last: app.buttons["spot-row-Seeded spot 9"])
            try shot(app, "dock-spots-\(size)")
            app.terminate()
        }
    }

    @MainActor
    func testTonightScrolledToBottomClearsTheDock() throws {
        for size in Size.allCases {
            let app = launch(size)
            XCTAssertTrue(el(app, "tonight.headline").waitForExistence(timeout: 30))
            scrollToBottom(app)
            try assertClearOfDock(app, "tonight-\(size)")
            try shot(app, "dock-tonight-\(size)")
            app.terminate()
        }
    }

    // MARK: The dock itself

    @MainActor
    func testDockFitsAtAccessibilityL() throws {
        var heights: [Size: CGFloat] = [:]
        for size in Size.allCases {
            let app = launch(size)
            let dock = el(app, "fieldDock")
            XCTAssertTrue(dock.waitForExistence(timeout: 15))
            heights[size] = dock.frame.height
            let share = dock.frame.height / app.frame.height
            print("DS_DOCK \(size) height=\(dock.frame.height) screen=\(app.frame.height) share=\(share)")
            if size == .axl {
                XCTAssertLessThanOrEqual(share, 0.18, "the dock takes \(Int(share * 100)) % of the screen at Accessibility L")
            }
            for name in ["tonight", "map", "sky", "spots", "tools"] {
                let item = app.buttons["fieldDock.\(name)"]
                XCTAssertTrue(item.exists, name)
                XCTAssertGreaterThanOrEqual(item.frame.height.rounded(), 44, "\(size) \(name): at least 44 pt tall")
                XCTAssertGreaterThanOrEqual(item.frame.width.rounded(), 44, "\(size) \(name): at least 44 pt wide")
                // Each label reports its own height and one line's height (FieldDock, Debug only).
                let label = el(app, "fieldDock.\(name).label")
                XCTAssertTrue(label.exists, "\(size) \(name): label measurement")
                let parts = (label.value as? String ?? "").split(separator: " ").compactMap { Double($0) }
                XCTAssertEqual(parts.count, 2, "\(size) \(name): \(label.value ?? "")")
                if parts.count == 2 {
                    XCTAssertLessThanOrEqual(parts[0], parts[1] + 0.5, "\(size) \(name): the label is one line (\(parts[0]) vs \(parts[1]) pt)")
                }
            }
            XCTAssertTrue(el(app, "field.brightness").isHittable, "\(size): brightness in reach")
            XCTAssertGreaterThan(el(app, "field.brightness").frame.minY, app.frame.height * 0.75, "\(size): brightness in the bottom quarter")
            try shot(app, "dock-\(size)")
            app.terminate()
        }
        print("DS_DOCK heights \(heights)")
    }

    // MARK: Helpers

    private func dockTop(_ app: XCUIApplication) -> CGFloat {
        el(app, "fieldDock").frame.minY
    }

    /// Asserts `last` (or, when nil, the lowest control on the screen) ends at
    /// or above the dock's top edge and takes a tap.
    @MainActor
    private func assertClearOfDock(_ app: XCUIApplication, _ name: String, last: XCUIElement? = nil,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let dock = el(app, "fieldDock")
        XCTAssertTrue(dock.waitForExistence(timeout: 5), "\(name): the field dock is shown", file: file, line: line)
        let top = dock.frame.minY
        let target = try last ?? lowestControl(app)
        guard let target, target.exists else {
            XCTFail("\(name): no control found", file: file, line: line)
            return
        }
        let note = "\(name): \(target.identifier.isEmpty ? target.label : target.identifier) maxY \(target.frame.maxY), dock minY \(top)"
        print("DS_DOCK \(note)")
        XCTAssertLessThanOrEqual(target.frame.maxY, top + 0.5, "\(note): the control ends under the dock", file: file, line: line)
        XCTAssertTrue(target.isHittable, "\(note): not hittable", file: file, line: line)
    }

    private static let controlTypes: Set<XCUIElement.ElementType> = [.button, .link, .textField, .slider, .switch, .toggle, .segmentedControl, .stepper]

    /// The control with the greatest maxY outside the dock, the navigation bar and the hidden tab bar.
    @MainActor
    private func lowestControl(_ app: XCUIApplication) throws -> XCUIElement? {
        let root = try app.snapshot()
        var best: (any XCUIElementSnapshot)?
        func walk(_ s: any XCUIElementSnapshot) {
            if s.identifier == "fieldDock" || s.elementType == .navigationBar || s.elementType == .tabBar { return }
            if Self.controlTypes.contains(s.elementType), s.frame.height > 0, s.frame.width > 0,
               s.frame.maxY > (best?.frame.maxY ?? -.infinity) {
                best = s
            }
            s.children.forEach(walk)
        }
        walk(root)
        guard let best else { return nil }
        let query = app.descendants(matching: best.elementType)
        if !best.identifier.isEmpty { return query.matching(identifier: best.identifier).firstMatch }
        return query.matching(NSPredicate(format: "label == %@", best.label)).firstMatch
    }

    /// Drags the content up from the left margin (clear of charts and
    /// sliders) until the lowest control stops moving.
    @MainActor
    private func scrollToBottom(_ app: XCUIApplication) {
        var last = CGFloat.infinity
        for _ in 0..<16 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.72))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.22)))
            let y = (try? lowestControl(app))??.frame.maxY ?? 0
            if abs(y - last) < 1 { return }
            last = y
        }
    }

    /// Standard mode, the gear editor, the in-app keypad: the calculator needs a profile.
    @MainActor
    private func ensureGear() {
        let app = launch(.std, tab: "tools", field: false)
        if app.buttons["tools.calc.starExposure"].waitForExistence(timeout: 5) {
            app.terminate()
            return
        }
        app.buttons["tools.addGear"].tap()
        let camera = app.textFields["gear.cameraName"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        camera.tap()
        camera.typeText("Sony A7 III")
        for (id, v) in [("gear.sensorWidth", "35.6"), ("gear.sensorHeight", "23.8"), ("gear.imageWidth", "6000"),
                        ("gear.imageHeight", "4000"), ("gear.focalLength", "20"), ("gear.maxAperture", "1.4")] {
            let field = app.textFields[id]
            field.swipeUpUntilVisible(in: app)
            field.tap()
            XCTAssertTrue(app.keys["keypad.done"].waitForExistence(timeout: 5))
            for ch in v { app.keys[ch == "." ? "keypad.point" : "keypad.\(ch)"].tap() }
            app.keys["keypad.done"].tap()
        }
        app.buttons["gear.save"].tap()
        XCTAssertTrue(app.buttons["tools.calc.starExposure"].waitForExistence(timeout: 5))
        app.terminate()
    }

    /// Attaches the screen and applies the design tour's field rule (no G or B > 12).
    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: screenshot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["DS_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        guard let cg = screenshot.image.cgImage else { return }
        let skipBottom = Int(34 * CGFloat(cg.height) / app.frame.height)
        let (bad, first) = DesignTourTests.nonRed(cg, threshold: 12, skipBottomRows: skipBottom)
        print("DS_SCAN \(name) bad=\(bad)")
        XCTAssertEqual(bad, 0, "\(name): \(bad) non-red pixels, first \(first ?? "")")
    }
}
