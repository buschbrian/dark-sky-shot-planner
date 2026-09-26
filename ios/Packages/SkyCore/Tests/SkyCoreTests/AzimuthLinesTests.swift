import Foundation
import Testing
@testable import SkyCore

@Suite("Map planner azimuth lines (M6)")
struct AzimuthLinesTests {
    static let canyonlands = try! Observer(latitude: 38.374031, longitude: -109.965416)

    @Test("lines match SkyCore's rise/transit/set and at-time azimuths")
    func linesMatchSkyCore() throws {
        let pin = Self.canyonlands
        let start = try ISO.date("2026-06-15T18:00:00Z")
        let time = try ISO.date("2026-06-16T06:00:00Z")
        let length = 50_000.0
        let lines = try AzimuthLines.plan(pin: pin, eventsFrom: start, at: time, lengthMeters: length)

        for object in AzimuthLines.mapObjects {
            let events = try SkyPositions.riseSetTransit(of: object, observer: pin, from: start, limitDays: 1)
            let expected: [(AzimuthLine.Event, HorizonEvent?)] = [(.rise, events.rise), (.transit, events.transit), (.set, events.set)]
            for (kind, event) in expected {
                let line = lines.first { $0.object == object && $0.event == kind }
                guard let event else {
                    #expect(line == nil)
                    continue
                }
                let l = try #require(line, "\(object) \(kind)")
                #expect(l.bearingDeg == event.position.azimuthDeg)
                #expect(l.date == event.date)
                #expect(l.start == pin.coordinate)
                // The drawn geodesic leaves the pin on that bearing and has the requested length.
                let leg = try #require(Geodesy.inverse(from: l.start, to: l.end))
                #expect(abs(Geodesy.signedAngle(leg.initialAzimuthDeg - event.position.azimuthDeg)) < 1e-8)
                #expect(abs(leg.distanceMeters - length) < 0.001)
            }
            let at = try #require(lines.first { $0.object == object && $0.event == .atTime })
            #expect(at.date == time)
            #expect(at.position == (try SkyPositions.position(of: object, at: time, observer: pin, refraction: .normal)))
        }
        // The GC rises, transits and sets inside this day (SkyPositionsTests.gcEvents).
        #expect(lines.filter { $0.object == .galacticCenter }.count == 4)
    }

    @Test("June sunset line at Canyonlands points west-northwest")
    func sunsetLine() throws {
        let lines = try AzimuthLines.plan(
            pin: Self.canyonlands, objects: [.sun], eventsFrom: ISO.date("2026-06-16T12:00:00Z"), at: nil, lengthMeters: 20_000)
        let set = try #require(lines.first { $0.event == .set })
        #expect((290...305).contains(set.bearingDeg))
        #expect(set.end.longitude < Self.canyonlands.longitude)
        #expect(set.end.latitude > Self.canyonlands.latitude)
        #expect(!lines.contains { $0.event == .atTime })
    }

    @Test("at-time line from the alt/az series: exact on a sample, close between samples")
    func seriesLine() throws {
        let pin = Self.canyonlands
        let start = try ISO.date("2026-06-16T04:00:00Z")
        let series = try SkyPositions.series(
            of: .galacticCenter, from: start, to: start.addingTimeInterval(4 * 3600), step: 600,
            observer: pin, refraction: .normal)
        let onSample = try #require(AzimuthLines.line(
            object: .galacticCenter, series: series, at: series[3].date, from: pin.coordinate, lengthMeters: 10_000))
        #expect(onSample.position == series[3].position)
        #expect(onSample.event == .atTime)

        // Between 10-minute samples the chord interpolation stays within 0.02°
        // (the diurnal circle's bow over a 2.5° step is under 0.01°).
        let mid = series[3].date.addingTimeInterval(300)
        let between = try #require(AzimuthLines.line(
            object: .galacticCenter, series: series, at: mid, from: pin.coordinate, lengthMeters: 10_000))
        let exact = try SkyPositions.position(of: .galacticCenter, at: mid, observer: pin, refraction: .normal)
        #expect(separationDeg(between.position, exact) < 0.02)

        #expect(AzimuthLines.line(
            object: .galacticCenter, series: series, at: start.addingTimeInterval(-1), from: pin.coordinate, lengthMeters: 10_000) == nil)
    }

    @Test("interpolation crosses north without swinging through south")
    func interpolationAcrossNorth() throws {
        let t0 = try ISO.date("2026-06-16T04:00:00Z")
        let series = [
            SkySample(date: t0, position: HorizontalPosition(altitudeDeg: 10, azimuthDeg: 358)),
            SkySample(date: t0.addingTimeInterval(600), position: HorizontalPosition(altitudeDeg: 10, azimuthDeg: 2)),
        ]
        let mid = try #require(SkyPositions.interpolated(series, at: t0.addingTimeInterval(300)))
        #expect(azimuthDelta(mid.azimuthDeg, 0) < 1e-9)
        #expect(abs(mid.altitudeDeg - 10) < 0.01)
    }
}
