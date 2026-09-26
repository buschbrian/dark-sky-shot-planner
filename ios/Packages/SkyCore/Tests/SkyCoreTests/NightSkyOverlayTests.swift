import Foundation
import Testing
@testable import SkyCore

@Suite("Night AR overlay model (M7)")
struct NightSkyOverlayTests {
    static let camera = CameraIntrinsics(fx: 2900, fy: 2900, cx: 1512, cy: 2016, width: 3024, height: 4032)
    static let candlestick = try! Observer(latitude: 38.374031, longitude: -109.965416)

    @Test("upright attitude points the boresight at the requested azimuth and pitch", arguments: [
        (180.0, 20.0), (0, 0), (90, -10), (271, 45), (359, 5),
    ])
    func upright(_ c: (az: Double, pitch: Double)) {
        let p = SkyProjector(attitude: .upright(facingAzimuth: c.az, pitchDeg: c.pitch), intrinsics: Self.camera)
        #expect(abs(p.boresight.altitudeDeg - c.pitch) < 1e-9)
        #expect(azimuthDelta(p.boresight.azimuthDeg, c.az) < 1e-9)
        // No roll: the point straight above the boresight sits on the centre column, above centre.
        let above = p.project(HorizontalPosition(altitudeDeg: c.pitch + 10, azimuthDeg: c.az))
        #expect(abs(above.pixel!.u - 1512) < 1e-6)
        #expect(above.pixel!.v < 2016)
        // Screen right is clockwise (az + 90 side).
        #expect(p.project(HorizontalPosition(altitudeDeg: c.pitch, azimuthDeg: c.az + 5)).pixel!.u > 1512)
    }

    @Test("upright level north matches the projection tests' hand-written attitude")
    func uprightMatchesRows() {
        let rows = RotationMatrix(rows: SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0))
        let a = DeviceAttitude.upright(facingAzimuth: 0, pitchDeg: 0).referenceToDevice
        for (x, y) in zip([a.m11, a.m12, a.m13, a.m21, a.m22, a.m23, a.m31, a.m32, a.m33],
                          [rows.m11, rows.m12, rows.m13, rows.m21, rows.m22, rows.m23, rows.m31, rows.m32, rows.m33]) {
            #expect(abs(x - y) < 1e-15)
        }
    }

    @Test("style: calibration rescues a poor compass, never an invalid one")
    func style() {
        #expect(OverlayStyle(heading: .confident(accuracyDeg: 5), calibrated: false) == .confident)
        #expect(OverlayStyle(heading: .poor(accuracyDeg: 25), calibrated: false) == .approximate(uncertaintyDeg: 25))
        #expect(OverlayStyle(heading: .poor(accuracyDeg: 25), calibrated: true) == .confident)
        #expect(OverlayStyle(heading: .unavailable, calibrated: false) == .approximate(uncertaintyDeg: nil))
        #expect(OverlayStyle(heading: .unavailable, calibrated: true) == .approximate(uncertaintyDeg: nil))
        let config = try! AppConfig.bundled().arOverlay
        #expect(!OverlayStyle(heading: HeadingConfidence(headingAccuracyDeg: -1, config: config), calibrated: true).isConfident)
    }

    @Test("16-wind compass points", arguments: [
        (0.0, "N", "north"), (11.2, "N", "north"), (11.3, "NNE", "north-northeast"), (90, "E", "east"),
        (180, "S", "south"), (202.5, "SSW", "south-southwest"), (348.8, "N", "north"), (-90, "W", "west"), (720, "N", "north"),
    ])
    func compass(_ c: (az: Double, abbr: String, name: String)) {
        #expect(CompassPoint.abbreviation(forAzimuth: c.az) == c.abbr)
        #expect(CompassPoint.name(forAzimuth: c.az) == c.name)
    }

    @Test("edge markers sit on the inset border in the target's direction")
    func edgeMarker() {
        let o = PixelPoint(u: 200, v: 400)
        func at(_ deg: Double) -> PixelPoint {
            EdgeMarker.point(from: o, direction: deg * .pi / 180, width: 400, height: 800, inset: 20)
        }
        #expect(at(0) == PixelPoint(u: 380, v: 400))
        #expect(at(180).u == 20 && abs(at(180).v - 400) < 1e-9)
        #expect(abs(at(90).u - 200) < 1e-9 && at(90).v == 780)
        #expect(abs(at(-90).u - 200) < 1e-9 && at(-90).v == 20)
        // 45° down-right from the centre hits the right edge first (the view is taller than wide).
        let diag = at(45)
        #expect(diag.u == 380 && abs(diag.v - 580) < 1e-9)
        // An origin outside the view is pulled in first.
        let outside = EdgeMarker.point(from: PixelPoint(u: -500, v: 400), direction: 0, width: 400, height: 800, inset: 20)
        #expect(outside == PixelPoint(u: 380, v: 400))
    }

    @Test("an arrow for a target behind the camera points the way to turn")
    func behindArrow() {
        let p = SkyProjector(attitude: .upright(facingAzimuth: 180, pitchDeg: 0), intrinsics: Self.camera)
        let behindRight = HorizontalPosition(altitudeDeg: 0, azimuthDeg: 300)  // facing S, 120° clockwise is to the right
        #expect(p.project(behindRight) == .behindCamera)
        let dir = p.screenDirection(toward: behindRight)!
        #expect(cos(dir) > 0.99)
    }

    @Test("scene positions are SkyCore's apparent positions")
    func scene() throws {
        let date = try ISO.date("2026-07-15T05:00:00Z")
        let obs = Self.candlestick
        let scene = try NightSkyScene.at(date, observer: obs)
        #expect(scene.bodies.map(\.object) == NightSkyScene.objects)
        #expect(scene.position(of: .galacticCenter) == Planner.gcPosition(obs, at: date, refraction: .normal))
        #expect(scene.position(of: .moon) == (try SkyPositions.position(of: .moon, at: date, observer: obs, refraction: .normal)))
        #expect(scene.moonIllumination == (try Planner.moonIllumination(at: date)))
        #expect(scene.milkyWay.count == 120)
        // The GC lies on the galactic mid-plane: the band passes within a step of it.
        let gc = try #require(scene.position(of: .galacticCenter))
        #expect(scene.milkyWay.map { separationDeg($0, gc) }.min()! < 2)
    }

    @Test("GC track spans the night with ticks on the whole hours")
    func gcTrack() throws {
        let window = try Planner.skyNightWindow(Self.candlestick, night: NightDate(year: 2026, month: 7, day: 14)!, timeZone: TimeZone(identifier: "America/Denver")!)
        let track = try GCTrack.across(window, observer: Self.candlestick)
        #expect(track.samples.first?.date == window.start)
        #expect(track.samples.last?.date == window.end)
        #expect(!track.hourTicks.isEmpty)
        for tick in track.hourTicks {
            #expect(tick.date > window.start && tick.date < window.end)
            #expect(tick.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) == 0)
            let expected = Planner.gcPosition(Self.candlestick, at: tick.date, refraction: .normal)
            #expect(tick.position == expected)
        }
    }

    @Test("night window falls back to 21:00–06:00 without astronomical darkness")
    func nightWindowFallback() throws {
        let tromso = try Observer(latitude: 69.65, longitude: 18.96)
        let tz = TimeZone(identifier: "Europe/Oslo")!
        let night = NightDate(year: 2026, month: 6, day: 21)!
        let window = try Planner.skyNightWindow(tromso, night: night, timeZone: tz)
        #expect(window.start == night.evening(in: tz))
        #expect(window.duration == 9 * 3600)
    }

    @Test("per-minute ephemeris interpolates to within 0.01° of the direct positions")
    func ephemeris() throws {
        let start = try ISO.date("2026-09-27T03:00:00Z")
        let span = TimeWindow(start: start, end: start.addingTimeInterval(20 * 60))
        let eph = try SkyEphemeris.compute(observer: Self.candlestick, span: span)
        #expect(eph.span == span)
        #expect(eph.scene(at: start.addingTimeInterval(-1)) == nil)
        #expect(eph.scene(at: span.end.addingTimeInterval(1)) == nil)
        #expect(eph.scene(at: start) == (try NightSkyScene.at(start, observer: Self.candlestick)))
        for seconds in [30.0, 61.5, 599, 1199] {
            let t = start.addingTimeInterval(seconds)
            let direct = try NightSkyScene.at(t, observer: Self.candlestick)
            let interp = try #require(eph.scene(at: t))
            #expect(interp.date == t)
            for (a, b) in zip(direct.bodies, interp.bodies) {
                #expect(a.object == b.object)
                #expect(separationDeg(a.position, b.position) < 0.01, "\(a.object) at +\(seconds) s")
            }
            #expect(zip(direct.milkyWay, interp.milkyWay).map { separationDeg($0, $1) }.max()! < 0.01)
            #expect(abs(direct.moonIllumination - interp.moonIllumination) < 1e-4)
        }
    }

    @Test("placing the image rect reproduces aspect fill")
    func placedRect() {
        let viewW = 402.0, viewH = 874.0
        let s = max(viewW / Self.camera.width, viewH / Self.camera.height)
        let w = Self.camera.width * s, h = Self.camera.height * s
        let placed = Self.camera.placed(inImageRectX: (viewW - w) / 2, y: (viewH - h) / 2, width: w, height: h, viewWidth: viewW, viewHeight: viewH)
        let filled = Self.camera.aspectFilled(toWidth: viewW, height: viewH)
        for (a, b) in [(placed.fx, filled.fx), (placed.fy, filled.fy), (placed.cx, filled.cx), (placed.cy, filled.cy), (placed.width, filled.width), (placed.height, filled.height)] {
            #expect(abs(a - b) < 1e-9)
        }
    }

    @Test("a stored calibration comes back only nearby and the same night")
    func storedCalibration() throws {
        let t = try ISO.date("2026-09-27T04:00:00Z")
        let stored = StoredCalibration(calibration: HeadingCalibration(offsetDeg: 7), target: "Moon", date: t, latitude: 38.374031, longitude: -109.965416)
        #expect(stored.isUsable(at: t.addingTimeInterval(3600), latitude: 38.374031, longitude: -109.965416))
        #expect(stored.isUsable(at: t.addingTimeInterval(3600), latitude: 38.378, longitude: -109.965416))  // ~440 m
        #expect(!stored.isUsable(at: t.addingTimeInterval(3600), latitude: 38.40, longitude: -109.965416))  // ~2.9 km
        #expect(!stored.isUsable(at: t.addingTimeInterval(7 * 3600), latitude: 38.374031, longitude: -109.965416))
        #expect(!stored.isUsable(at: t.addingTimeInterval(-60), latitude: 38.374031, longitude: -109.965416))
        let decoded = try JSONDecoder().decode(StoredCalibration.self, from: JSONEncoder().encode(stored))
        #expect(decoded == stored)
    }
}
