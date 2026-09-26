import Foundation
import Testing
@testable import SkyCore

@Suite("Map planner drawn geometry (M6)")
struct MapPlannerTests {
    static let canyonlands = try! Observer(latitude: 38.374031, longitude: -109.965416)
    static let denver = TimeZone(identifier: "America/Denver")!
    static let june15 = NightDate(year: 2026, month: 6, day: 15)!

    /// Every vertex the map draws lies on the SkyCore azimuth, as seen from the pin.
    @Test("drawn lines match SkyCore rise/transit/set and at-time azimuths")
    func drawnLinesMatchSkyCore() throws {
        let pin = Self.canyonlands
        let plan = try MapPlanner.plan(pin: pin, night: Self.june15, timeZone: Self.denver)
        let time = try ISO.date("2026-06-16T06:00:00Z")
        let length = 45_000.0
        let features = MapPlanner.features(plan.lines(at: time, lengthMeters: length))
        let noon = Self.june15.evening(in: Self.denver).addingTimeInterval(-9 * 3600)

        var checked = 0
        for object in AzimuthLines.mapObjects {
            let events = try SkyPositions.riseSetTransit(of: object, observer: pin, from: noon, limitDays: 1)
            for (kind, event) in [(AzimuthLine.Event.rise, events.rise), (.transit, events.transit), (.set, events.set)] {
                let drawn = features.filter { $0.line.object == object && $0.line.event == kind }
                guard let event else { #expect(drawn.isEmpty); continue }
                let f = try #require(drawn.first, "\(object) \(kind)")
                #expect(drawn.count == 1)
                #expect(f.line.date == event.date)
                try expectOnBearing(f, bearing: event.position.azimuthDeg, pin: pin.coordinate, length: length)
                checked += 1
            }
            let at = try #require(features.first { $0.line.object == object && $0.line.event == .atTime })
            let exact = try SkyPositions.position(of: object, at: time, observer: pin, refraction: .normal)
            // Interpolated from the 5-minute series; the drawn bearing is that position's azimuth.
            #expect(azimuthDelta(at.line.bearingDeg, exact.azimuthDeg) < 0.02)
            #expect(abs(at.line.position.altitudeDeg - exact.altitudeDeg) < 0.02)
            try expectOnBearing(at, bearing: at.line.bearingDeg, pin: pin.coordinate, length: length)
        }
        // Sun, Moon and GC each rise, transit and set on this date.
        #expect(checked == 9)
    }

    private func expectOnBearing(_ f: MapLineFeature, bearing: Double, pin: GeoCoordinate, length: Double) throws {
        #expect(f.coordinates.first == pin)
        #expect(f.coordinates.last == f.line.end)
        #expect(f.coordinates.count >= 3, "long lines are densified")
        var previous = 0.0
        for (i, v) in f.coordinates.enumerated().dropFirst() {
            let leg = try #require(Geodesy.inverse(from: pin, to: v))
            #expect(azimuthDelta(leg.initialAzimuthDeg, bearing) < 1e-6, "vertex \(i) of \(f.line.object) \(f.line.event)")
            #expect(leg.distanceMeters > previous)
            #expect(leg.distanceMeters - previous <= MapPlanner.maxSegmentMeters + 1e-6)
            previous = leg.distanceMeters
        }
        #expect(abs(previous - length) < 0.001)
    }

    @Test("the scrubber window runs from before sunset to after sunrise and holds the darkness")
    func window() throws {
        let plan = try MapPlanner.plan(pin: Self.canyonlands, night: Self.june15, timeZone: Self.denver)
        let sunset = try #require(plan.events[.sun]?.set?.date)
        #expect(plan.window.start == sunset.addingTimeInterval(-1800))
        let dark = try #require(Planner.darknessWindow(Self.canyonlands, evening: Self.june15.evening(in: Self.denver)).window)
        #expect(plan.window.start < dark.start && plan.window.end > dark.end)
        #expect((8...12).contains(plan.window.duration / 3600))
        for object in AzimuthLines.mapObjects {
            let s = try #require(plan.series[object])
            #expect(s.first?.date == plan.window.start)
            #expect(s.last?.date == plan.window.end)
        }
        // Outside the window there is no at-time line.
        let before = plan.lines(at: plan.window.start.addingTimeInterval(-60), lengthMeters: 1000)
        #expect(!before.contains { $0.event == .atTime })
    }

    @Test("line length follows the zoom so the end label stays on screen")
    func lengthFollowsZoom() {
        let z10 = MapPlanner.lineLengthMeters(zoom: 10, latitude: 38.4, viewportShortSidePoints: 400)
        let z11 = MapPlanner.lineLengthMeters(zoom: 11, latitude: 38.4, viewportShortSidePoints: 400)
        #expect(abs(z10 / z11 - 2) < 1e-9)
        // At zoom 10, 38.4° N, a point is ~59.9 m: 0.42 × 400 pt ≈ 10.06 km.
        #expect(abs(z10 - 10_064) < 5)
        #expect(MapPlanner.lineLengthMeters(zoom: 0, latitude: 38.4, viewportShortSidePoints: 400) == 600_000)
        #expect(MapPlanner.lineLengthMeters(zoom: 22, latitude: 38.4, viewportShortSidePoints: 400) == 100)
        // A 600 km line stays within the vertex cap.
        let long = AzimuthLines.line(
            object: .sun, event: .set, date: .now, position: HorizontalPosition(altitudeDeg: 0, azimuthDeg: 300),
            from: Self.canyonlands.coordinate, lengthMeters: 600_000)
        #expect(MapPlanner.feature(long).coordinates.count == 257)
    }

    @Test("labels name the object, event, local time and azimuth")
    func labels() {
        let date = Date(timeIntervalSince1970: 1_781_577_840) // 2026-06-16T02:44:00Z = 20:44 MDT
        let set = AzimuthLines.line(
            object: .sun, event: .set, date: date, position: HorizontalPosition(altitudeDeg: -0.8, azimuthDeg: 299.6),
            from: Self.canyonlands.coordinate, lengthMeters: 1000)
        #expect(MapPlanner.label(for: set, timeZone: Self.denver) == "Sun set 20:44 · 300°")
        #expect(!MapPlanner.feature(set).belowHorizon)
        let at = AzimuthLines.line(
            object: .galacticCenter, event: .atTime, date: date, position: HorizontalPosition(altitudeDeg: -3.2, azimuthDeg: 359.7),
            from: Self.canyonlands.coordinate, lengthMeters: 1000)
        #expect(MapPlanner.label(for: at, timeZone: Self.denver) == "GC 20:44 · 0° · below horizon")
        #expect(MapPlanner.feature(at).belowHorizon)
        let moon = AzimuthLines.line(
            object: .moon, event: .atTime, date: date, position: HorizontalPosition(altitudeDeg: 12.4, azimuthDeg: 118.2),
            from: Self.canyonlands.coordinate, lengthMeters: 1000)
        #expect(MapPlanner.label(for: moon, timeZone: Self.denver) == "Moon 20:44 · 118° · 12° up")
    }
}
