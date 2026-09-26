import Foundation
import Testing
@testable import SkyCore

@Suite("Sky positions, Milky Way band, rise/set/transit")
struct SkyPositionsTests {
    static let canyonlands = try! Observer(latitude: 38.374031, longitude: -109.965416)

    @Test("sun sits at -18° (geometric) at the planner's darkness edges")
    func sunAtDarknessEdges() throws {
        let obs = Self.canyonlands
        let (window, _) = try Planner.darknessWindow(obs, evening: ISO.date("2026-06-16T03:00:00Z"))
        let w = try #require(window)
        for edge in [w.start, w.end] {
            let sun = try SkyPositions.position(of: .sun, at: edge, observer: obs, refraction: .none)
            #expect(abs(sun.altitudeDeg + 18) < 0.01)
        }
    }

    @Test("series samples every step, inclusive of the end")
    func seriesSampling() throws {
        let start = try ISO.date("2026-06-16T04:00:00Z")
        let end = start.addingTimeInterval(3600)
        for object in SkyObject.allCases {
            let samples = try SkyPositions.series(
                of: object, from: start, to: end, step: 600, observer: Self.canyonlands, refraction: .normal)
            #expect(samples.count == 7)
            #expect(samples.allSatisfy { (-90...90).contains($0.position.altitudeDeg) && (0..<360).contains($0.position.azimuthDeg) })
        }
    }

    @Test("GC series with no refraction equals the web GC function")
    func gcSeriesMatchesPlanner() throws {
        let start = try ISO.date("2026-06-16T04:42:18.530Z")
        let samples = try SkyPositions.series(
            of: .galacticCenter, from: start, to: start.addingTimeInterval(7200), step: 1800,
            observer: Self.canyonlands, refraction: .none)
        for s in samples {
            #expect(s.position == Planner.gcPosition(Self.canyonlands, at: s.date))
        }
    }

    @Test("Milky Way band: l=0 lands on the GC, l=180 on its antipode")
    func milkyWayBandGeometry() throws {
        let when = try ISO.date("2026-06-16T07:27:18.530Z")
        let band = try SkyPositions.milkyWayBand(at: when, observer: Self.canyonlands, stepDeg: 5, refraction: .none)
        #expect(band.count == 72)
        let gc = Planner.gcPosition(Self.canyonlands, at: when)
        let center = try #require(band.first { $0.galacticLongitudeDeg == 0 }).position
        let anti = try #require(band.first { $0.galacticLongitudeDeg == 180 }).position
        // Both are precessed to the date; Sgr A* sits at l = 359.944°,
        // b = −0.046°, i.e. 0.07° from (0, 0).
        #expect(separationDeg(center, gc) < 0.1)
        #expect(abs(anti.altitudeDeg + center.altitudeDeg) < 0.01)
        #expect(abs(azimuthDelta(anti.azimuthDeg, center.azimuthDeg) - 180) < 0.01)
    }

    @Test("moonrise matches the golden great-basin moonrise and faces east")
    func moonRiseAzimuth() throws {
        let obs = try observer(38.98, -114.3)
        let result = try SkyPositions.riseSetTransit(
            of: .moon, observer: obs, from: ISO.date("2026-08-08T04:24:27.001Z"), limitDays: 1)
        let rise = try #require(result.rise)
        #expect(abs(rise.date.timeIntervalSince(try ISO.date("2026-08-08T07:44:23.877Z"))) < 1)
        #expect((45...135).contains(rise.position.azimuthDeg))
        #expect(abs(rise.position.altitudeDeg) < 1)
    }

    @Test("June sun sets in the northwest and transits due south")
    func sunEvents() throws {
        let result = try SkyPositions.riseSetTransit(
            of: .sun, observer: Self.canyonlands, from: ISO.date("2026-06-16T12:00:00Z"), limitDays: 1)
        let set = try #require(result.set)
        let transit = try #require(result.transit)
        #expect((290...305).contains(set.position.azimuthDeg))
        #expect(azimuthDelta(transit.position.azimuthDeg, 180) < 0.5)
        #expect(transit.position.altitudeDeg > 74)
    }

    @Test("GC rises and sets at 0° and transits due south at its peak")
    func gcEvents() throws {
        let obs = Self.canyonlands
        let result = try SkyPositions.riseSetTransit(
            of: .galacticCenter, observer: obs, from: ISO.date("2026-06-15T18:00:00Z"), limitDays: 1)
        let rise = try #require(result.rise)
        let transit = try #require(result.transit)
        let set = try #require(result.set)
        #expect(rise.date < transit.date && transit.date < set.date)
        #expect(abs(rise.position.altitudeDeg) < 0.01)
        #expect(abs(set.position.altitudeDeg) < 0.01)
        #expect(azimuthDelta(transit.position.azimuthDeg, 180) < 0.1)
        // Peak altitude for a fixed star: 90 − |lat − dec of date|.
        let dec = Planner.gcEquatorOfDate(at: transit.date).decDeg
        #expect(abs(transit.position.altitudeDeg - (90 - abs(obs.latitude - dec))) < 0.05)
        // The golden canyonlands GC peak (22.6° at 07:27 UTC) is this transit.
        #expect(abs(transit.date.timeIntervalSince(try ISO.date("2026-06-16T07:27:18.530Z"))) < 5 * 60)
    }
}
