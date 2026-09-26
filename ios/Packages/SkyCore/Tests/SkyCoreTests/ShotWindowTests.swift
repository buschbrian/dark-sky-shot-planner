import Foundation
import Testing
@testable import SkyCore

/// M11: the shot window. Golden cases come from the Candlestick Camp horizon
/// cases in `shared/golden/night-report.json` (the web planner's numbers):
/// with the GC as the target and no minimum altitude, the shot window is
/// exactly the planner's `terrain.gc_windows`.
@Suite("Shot window")
struct ShotWindowTests {
    static let camp = (lat: 38.374031, lon: -109.965416)
    static let denver = TimeZone(identifier: "America/Denver")!

    func camp() throws -> Observer { try observer(Self.camp.lat, Self.camp.lon) }
    func candlestick() throws -> HorizonProfile { try HorizonProfile.bundled("candlestick-camp") }

    @Test("GC over the Candlestick skyline equals the golden terrain windows", arguments: try GoldenHorizonFile.load().horizon_cases)
    func goldenGCWindows(_ golden: GoldenHorizonFile.Case) throws {
        let tolerance = try GoldenHorizonFile.load().tolerance.time_s
        let shot = try ShotWindow.compute(
            observer(golden.latitude, golden.longitude), evening: ISO.date(golden.evening_utc),
            horizon: HorizonProfile.parse(csv: String(decoding: Repo.data(golden.horizon_profile), as: UTF8.self)),
            target: .galacticCore)
        let expected = golden.expected.terrain
        #expect(shot.windows.count == expected.gc_windows.count)
        for (w, e) in zip(shot.windows, expected.gc_windows) {
            #expect(abs(w.start.timeIntervalSince(try ISO.date(e.start))) <= tolerance)
            #expect(abs(w.end.timeIntervalSince(try ISO.date(e.end))) <= tolerance)
            #expect(w.minutes == e.minutes)
        }
        #expect(shot.usableMinutes == expected.gc_minutes)
        #expect((shot.clears == nil) == (expected.gc_clears_skyline == nil))
        if let c = shot.clears, let e = expected.gc_clears_skyline {
            #expect(abs(c.timeIntervalSince(try ISO.date(e))) <= tolerance)
        }
        #expect((shot.drops == nil) == (expected.gc_drops_behind_skyline == nil))
        #expect(shot.terrainAware)
    }

    @Test("May 6: the core clears the ridge, then the Moon rises over it")
    func mayEdges() throws {
        let shot = try ShotWindow.compute(
            camp(), evening: ISO.date("2026-05-07T03:00:00Z"), horizon: candlestick(), target: .galacticCore)
        let best = try #require(shot.best)
        #expect(best.opensBy == .targetClears)
        #expect(best.closesBy == .moonrise)
        #expect(shot.clearsOverTerrain)
        #expect(best.start == shot.clears)
        #expect(best.end == shot.night.moonrise)
        // The track spans the window every 5 min, and the core is over the skyline throughout.
        #expect(shot.track.first?.date == best.start)
        #expect(shot.track.last?.date == best.end)
        #expect(shot.track.count == Int((best.end.timeIntervalSince(best.start) / 300).rounded(.up)) + 1)
        #expect(shot.track.dropFirst().allSatisfy { $0.clearanceDeg > 0 })
        #expect(abs(try #require(shot.track.first).clearanceDeg) < 0.01)
        let peak = try #require(shot.peak)
        #expect(abs(peak.position.altitudeDeg - 14.1) < 0.1)
        #expect(ShotText.astronomy(shot, clock: ShotText.clock24(Self.denver))
            == "Core clears the ridge 00:15, 1 h 21 min moon-free")
    }

    @Test("June 24: the core is up at dusk; the window opens at moonset and runs to dawn")
    func juneEdges() throws {
        let shot = try ShotWindow.compute(
            camp(), evening: ISO.date("2026-06-25T03:00:00Z"), horizon: candlestick(), target: .galacticCore)
        let best = try #require(shot.best)
        #expect(shot.clears == nil)
        #expect(best.opensBy == .moonset)
        #expect(best.closesBy == .dawn)
        #expect(ShotText.astronomy(shot, clock: ShotText.clock24(Self.denver))
            == "Core up, Moon behind terrain 02:14, 1 h 46 min moon-free")
    }

    @Test("a minimum altitude above the ridge shortens the window and is named")
    func minimumAltitude() throws {
        let evening = try ISO.date("2026-06-25T03:00:00Z")
        let plain = try ShotWindow.compute(camp(), evening: evening, horizon: candlestick(), target: .galacticCore)
        let high = try ShotWindow.compute(
            camp(), evening: evening, horizon: candlestick(), target: .galacticCore, minAltitudeDeg: 15)
        #expect(high.usableMinutes < plain.usableMinutes)
        #expect(high.usableMinutes > 0)
        #expect(high.track.allSatisfy { $0.position.altitudeDeg >= 15 - 0.01 })
        #expect(high.minAltitudeDeg == 15)
        // The GC sinks through 15° before dawn, so the window now closes on the target.
        #expect(try #require(high.best).closesBy == .targetDrops)
    }

    @Test("with no profile the horizon is flat at 0° and says so")
    func flatHorizon() throws {
        let evening = try ISO.date("2026-05-07T03:00:00Z")
        let flat = try ShotWindow.compute(camp(), evening: evening, horizon: nil, target: .galacticCore)
        let night = try Planner.planNight(camp(), evening: evening)
        #expect(!flat.terrainAware)
        #expect(flat.night == night)
        #expect(flat.track.allSatisfy { $0.position.altitudeDeg >= -0.01 })
        #expect(flat.windows.allSatisfy { w in night.moonFreeWindows.contains { $0.start <= w.start && w.end <= $0.end } })
        if flat.clears != nil { #expect(ShotText.astronomy(flat, clock: ShotText.clock24(Self.denver)).contains("clears the horizon")) }
    }

    @Test("a 60° wall: the core never clears")
    func wall() throws {
        let shot = try ShotWindow.compute(
            camp(), evening: ISO.date("2026-05-07T03:00:00Z"), horizon: .flat(60), target: .galacticCore)
        #expect(shot.windows.isEmpty)
        #expect(shot.shortfall == .neverClears)
        #expect(shot.track.isEmpty)
        #expect(ShotText.headline(shot, readout: nil, clock: ShotText.clock24(Self.denver))
            == "Core never clears the ridge in darkness")
    }

    @Test("full moon 2026-09-26: the core is up only while the Moon is; the Moon itself fills the night")
    func fullMoon() throws {
        let evening = try ISO.date("2026-09-27T03:00:00Z")
        let gc = try ShotWindow.compute(camp(), evening: evening, horizon: nil, target: .galacticCore)
        #expect(gc.night.moonFreeMinutes == 0)
        #expect(!gc.targetUp.isEmpty)
        #expect(gc.shortfall == .onlyWithMoon)

        let moon = try ShotWindow.compute(camp(), evening: evening, horizon: nil, target: .moon)
        let dark = try #require(moon.night.darkness)
        let best = try #require(moon.best)
        #expect(!ShotTarget.moon.needsMoonFree)
        #expect(best.opensBy == .dusk)
        #expect(best.closesBy == .dawn)
        #expect(best.start == dark.start && best.end == dark.end)
        #expect(ShotText.astronomy(moon, clock: ShotText.clock24(Self.denver)).hasSuffix("in darkness"))
    }

    @Test("the Moon as a target rises over the skyline when the planner says it does")
    func moonTargetMatchesPlanner() throws {
        let shot = try ShotWindow.compute(
            camp(), evening: ISO.date("2026-05-07T03:00:00Z"), horizon: candlestick(), target: .moon)
        let rise = try #require(shot.clears)
        let planner = try #require(shot.night.moonrise)
        #expect(abs(rise.timeIntervalSince(planner)) < 1)
        #expect(try #require(shot.best).opensBy == .targetClears)
    }

    @Test("planets use the refracted apparent position")
    func planetTrack() throws {
        let obs = try camp()
        let shot = try ShotWindow.compute(obs, evening: ISO.date("2026-09-17T03:00:00Z"), horizon: nil, target: .planet(.saturn))
        let sample = try #require(shot.track.dropFirst(3).first)
        let direct = try SkyPositions.position(of: .saturn, at: sample.date, observer: obs, refraction: .normal)
        #expect(abs(sample.position.altitudeDeg - direct.altitudeDeg) < 1e-9)
        #expect(abs(sample.clearanceDeg - direct.altitudeDeg) < 1e-9)
        #expect(ShotTarget.planet(.saturn).name == "Saturn")
    }

    @Test("a fixed target at the GC's J2000 coordinates precesses exactly like the GC")
    func fixedPrecession() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let fixed = ShotTarget.equatorOfDate(raHours: Planner.gcRAHours, decDeg: Planner.gcDecDeg, at: date)
        let gc = Planner.gcEquatorOfDate(at: date)
        #expect(fixed.raHours == gc.raHours)
        #expect(fixed.decDeg == gc.decDeg)
    }

    @Test("Vega on a September evening is high in the west-northwest, not moving with the Sun")
    func vega() throws {
        let vega = try #require(FixedTarget.catalog.first { $0.name == "Vega" })
        let shot = try ShotWindow.compute(camp(), evening: ISO.date("2026-09-17T03:00:00Z"), horizon: nil, target: .fixed(vega))
        let first = try #require(shot.track.first)
        #expect(first.position.altitudeDeg > 60)
        #expect(shot.clears == nil) // already up at dusk
    }

    @Test("the arch counts only while its lowest point clears; the core end limits it")
    func arch() throws {
        let obs = try camp()
        let evening = try ISO.date("2026-06-25T03:00:00Z")
        let arch = try ShotWindow.compute(obs, evening: evening, horizon: candlestick(), target: .milkyWayArch(.coreToCygnus))
        let gc = try ShotWindow.compute(obs, evening: evening, horizon: candlestick(), target: .galacticCore)
        #expect(arch.totalMinutes <= gc.totalMinutes + 2)
        for s in arch.track {
            let core = Planner.gcPosition(obs, at: s.date)
            let skyline = try candlestick()
            #expect(s.clearanceDeg <= core.altitudeDeg - skyline.altitudeDeg(atAzimuth: core.azimuthDeg) + 0.2)
        }
        #expect(MilkyWaySegment(name: "wrap", fromL: 340, toL: 20).longitudes(stepDeg: 10) == [340, 350, 0, 10, 20])
    }

    @Test("target ids are stable and distinct")
    func ids() {
        let ids = ShotTarget.presets.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ShotTarget.galacticCore.id == "gc")
    }
}
