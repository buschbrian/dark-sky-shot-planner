import CAstronomy
import Foundation
import Testing
@testable import SkyCore

@Suite("Bundled star catalogue and constellation figures")
struct StarCatalogTests {
    static let catalog = try! StarCatalog.bundled()

    @Test("BSC5 to V 6.5: complete, sorted, sane values")
    func stars() {
        let c = Self.catalog
        #expect(c.stars.count == 8404)
        #expect(zip(c.stars, c.stars.dropFirst()).allSatisfy { $0.hr < $1.hr })
        for s in c.stars {
            #expect((0..<360).contains(s.raDeg) && (-90...90).contains(s.decDeg))
            #expect(s.vmag <= 6.5 && s.vmag >= -1.5)
            // Carbon stars (HR 423, 1648, 5644) reach B−V 3.9.
            if let bv = s.bv { #expect((-0.5...4).contains(bv)) }
        }
        #expect(c.stars.filter { $0.vmag <= 6 }.count > 4900)
    }

    /// SIMBAD J2000 (ICRS) positions; BSC5 rounds to 0.1 s and 1″.
    @Test("catalogue positions and magnitudes match published values", arguments: [
        (2491, "Sirius", 101.28715533, -16.71611586, -1.46),
        (7001, "Vega", 279.23473479, 38.78368896, 0.03),
        (424, "Polaris", 37.95456067, 89.26410897, 2.02),
        (2061, "Betelgeuse", 88.79293899, 7.40706399, 0.50),
    ])
    func published(_ c: (hr: Int, name: String, ra: Double, dec: Double, v: Double)) throws {
        let star = try #require(Self.catalog.star(hr: c.hr))
        #expect(Self.catalog.names[c.hr] == c.name)
        let sep = angle(SkyRotation.vector(raDeg: star.raDeg, decDeg: star.decDeg), SkyRotation.vector(raDeg: c.ra, decDeg: c.dec))
        #expect(sep * 3600 < 2, "\(c.name) is \(sep * 3600)″ from SIMBAD")
        #expect(abs(star.vmag - c.v) < 0.011)
    }

    @Test("constellation figures: all 88, every vertex a catalogue star, no degenerate segment")
    func figures() {
        let figures = Self.catalog.constellations
        #expect(figures.count == 88)
        #expect(Set(figures.map(\.abbreviation)).count == 88)
        for f in figures {
            #expect(!f.lines.isEmpty)
            for line in f.lines {
                #expect(line.count >= 2)
                for (a, b) in zip(line, line.dropFirst()) {
                    #expect(a != b, "\(f.abbreviation) joins HR \(a) to itself")
                    let sa = Self.catalog.star(hr: a)!, sb = Self.catalog.star(hr: b)!
                    let sep = angle(SkyRotation.vector(raDeg: sa.raDeg, decDeg: sa.decDeg), SkyRotation.vector(raDeg: sb.raDeg, decDeg: sb.decDeg))
                    // The longest real segment (in Eridanus/Hydra/Argo) is under 30°.
                    #expect(sep > 0.05 && sep < 30, "\(f.abbreviation) segment HR \(a)–\(b) is \(sep)°")
                }
            }
        }
    }

    /// astronomy-engine's `Constellation` uses the IAU boundaries (Roman 1987).
    @Test("figure stars lie inside their own IAU constellation")
    func boundaries() {
        var inside = 0, total = 0
        for f in Self.catalog.constellations {
            var own = 0
            for hr in f.starHRs {
                let s = Self.catalog.star(hr: hr)!
                let found = Astronomy_Constellation(s.raDeg / 15, s.decDeg)
                let symbol = found.symbol.map { String(cString: $0) }
                if symbol == f.abbreviation { own += 1 }
                total += 1
            }
            inside += own
            // Shared stars (Alpheratz in And/Peg, Elnath in Tau/Aur) are few per figure.
            #expect(Double(own) / Double(f.starHRs.count) >= 0.6, "\(f.abbreviation): \(own)/\(f.starHRs.count)")
        }
        #expect(Double(inside) / Double(total) > 0.95)
    }

    @Test("Orion's belt is Alnitak–Alnilam–Mintaka")
    func orion() throws {
        let orion = try #require(Self.catalog.constellations.first { $0.abbreviation == "Ori" })
        #expect(orion.name == "Orion")
        #expect(orion.lines.contains([1948, 1903, 1852]))
    }
}

@Suite("Apparent star places")
struct StarFieldTests {
    static let catalog = StarCatalogTests.catalog
    static let candlestick = try! Observer(latitude: 38.374031, longitude: -109.965416)

    /// From `ios/scripts/star-reference.cjs` (astronomy-engine 2.1.19, npm):
    /// SIMBAD positions + Hipparcos proper motions, DefineStar, Equator (of
    /// date, aberration), Horizon (normal refraction), Candlestick Camp.
    static let reference: [(hr: Int, iso: String, raOfDateHours: Double, decOfDate: Double, alt: Double, az: Double)] = [
        (2491, "2026-07-15T05:00:00Z", 6.771706, -16.75137, -59.9547, 309.9369),
        (7001, "2026-07-15T05:00:00Z", 18.631174, 38.80929, 73.3396, 81.8138),
        (424, "2026-07-15T05:00:00Z", 3.094292, 89.37073, 37.8595, 0.4186),
        (2491, "2026-12-15T12:00:00Z", 6.772791, -16.75269, 16.1370, 232.3460),
        (7001, "2026-12-15T12:00:00Z", 18.630480, 38.80960, 2.3625, 39.5453),
        (424, "2026-12-15T12:00:00Z", 3.148958, 89.38075, 38.2124, 359.2464),
    ]

    @Test("Sirius, Vega, Polaris: RA/Dec of date and alt/az agree with astronomy-engine", arguments: 0..<6)
    func againstAstronomyEngine(_ n: Int) throws {
        let r = Self.reference[n]
        let date = try ISO.date(r.iso)
        let field = StarField(catalog: Self.catalog, epoch: date)
        let i = try #require(Self.catalog.index(ofHR: r.hr))
        let eq = field.equatorOfDate(ofStarAt: i, at: date)
        // Position on the sky, so RA differences shrink by cos δ (Polaris).
        let sep = angle(SkyRotation.vector(raDeg: eq.raHours * 15, decDeg: eq.decDeg),
                        SkyRotation.vector(raDeg: r.raOfDateHours * 15, decDeg: r.decOfDate))
        // BSC5 vs SIMBAD positions and proper motions differ by ~1″.
        #expect(sep * 3600 < 3, "HR \(r.hr) \(r.iso): \(sep * 3600)″ from astronomy-engine")
        let pos = field.position(ofStarAt: i, at: date, observer: Self.candlestick)
        #expect(abs(pos.altitudeDeg - r.alt) < 0.002, "alt \(pos.altitudeDeg) vs \(r.alt)")
        #expect(azimuthDelta(pos.azimuthDeg, r.az) * cos(r.alt * .pi / 180) < 0.002 || abs(r.alt) > 89)
    }

    /// `ios/scripts/star-reference.cjs`: the 20 brightest stars of the
    /// bundled file itself (same positions and proper motions), through
    /// astronomy-engine's DefineStar + Equator (of date, aberration) + Horizon
    /// (normal refraction), so this pins SkyCore's pipeline.
    static let brightest: [(hr: Int, alt: Double, az: Double)] = [
        (2491, -59.9547, 309.9372), (2326, -70.8701, 215.1713), (5340, 47.4675, 255.6914), (5459, -13.4327, 197.8379),
        (7001, 73.3397, 81.8143), (1708, -4.9783, 358.9148), (1713, -59.5663, 358.3340), (2943, -34.1551, 313.2067),
        (472, -50.5180, 136.3460), (2061, -42.7325, 344.9252), (5267, -15.4538, 201.8736), (7557, 43.6797, 118.7977),
        (1457, -34.0508, 10.1792), (6134, 24.4523, 190.1592), (5056, 17.7008, 239.0533), (2990, -13.9218, 325.2895),
        (8728, -14.8828, 115.6361), (4853, -21.5418, 209.6259), (7924, 51.0166, 62.3102), (4730, -25.6386, 208.3026),
    ]

    @Test("20 brightest stars: alt/az within 0.05° of astronomy-engine (Candlestick Camp, 2026-07-15 05:00 UTC)")
    func twentyBrightest() throws {
        let date = try ISO.date("2026-07-15T05:00:00Z")
        let field = StarField(catalog: Self.catalog, epoch: date)
        #expect(Self.brightest.count == 20)
        var worst = 0.0
        for r in Self.brightest {
            let i = try #require(Self.catalog.index(ofHR: r.hr))
            let pos = field.position(ofStarAt: i, at: date, observer: Self.candlestick)
            let sep = SkyBrightness.angularSeparationDeg(pos, HorizontalPosition(altitudeDeg: r.alt, azimuthDeg: r.az))
            worst = max(worst, sep)
            #expect(sep < 0.05, "HR \(r.hr): \(sep)°")
        }
        // In practice the agreement is far tighter than the 0.05° bound.
        #expect(worst < 0.005, "worst \(worst)°")
    }

    @Test("apparent altitude includes standard refraction like Horizon()")
    func refraction() throws {
        let date = try ISO.date("2026-12-15T12:00:00Z")
        let field = StarField(catalog: Self.catalog, epoch: date)
        let vega = try #require(Self.catalog.index(ofHR: 7001))
        let geometric = HorizontalPosition(reference: SkyRotation.eqjToReference(at: date, observer: Self.candlestick) * field.apparentEQJ[vega])
        let apparent = field.position(ofStarAt: vega, at: date, observer: Self.candlestick)
        // About 0.3° at 2° up.
        let lift = apparent.altitudeDeg - geometric.altitudeDeg
        #expect(abs(lift - Astronomy_Refraction(REFRACTION_NORMAL, geometric.altitudeDeg)) < 1e-9)
        #expect(lift > 0.25 && lift < 0.35)
        #expect(azimuthDelta(apparent.azimuthDeg, geometric.azimuthDeg) < 1e-9)
    }

    @Test("per-frame projection places Vega where the projector puts its alt/az")
    func projection() throws {
        let date = try ISO.date("2026-07-15T05:00:00Z")
        let field = StarField(catalog: Self.catalog, epoch: date)
        let vega = try #require(Self.catalog.index(ofHR: 7001))
        let pos = field.position(ofStarAt: vega, at: date, observer: Self.candlestick)
        let camera = CameraIntrinsics(fx: 800, fy: 800, cx: 400, cy: 800, width: 800, height: 1600)
        let projector = SkyProjector(attitude: .upright(facingAzimuth: pos.azimuthDeg, pitchDeg: pos.altitudeDeg - 5), intrinsics: camera)
        let stars = field.project(
            through: projector, eqjToReference: SkyRotation.eqjToReference(at: date, observer: Self.candlestick),
            magnitudeLimit: 6.5, extinction: .typical, horizon: HorizonLookup(nil))
        let projected = try #require(stars.first { $0.index == vega })
        let expected = try #require(projector.project(pos).pixel)
        #expect(abs(projected.u - expected.u) < 1e-6 && abs(projected.v - expected.v) < 1e-6)
        #expect(abs(projected.apparentMagnitude - (0.03 + Extinction.typical.deltaMagnitude(altitudeDeg: pos.altitudeDeg))) < 1e-9)
        // Brightest first, all inside the frame margin and above the horizon.
        #expect(stars.allSatisfy { $0.altitudeDeg > -1 && $0.u > -8 && $0.u < 808 })
        #expect(stars.count > 50)
    }

    @Test("terrain hides stars behind it")
    func terrain() throws {
        let date = try ISO.date("2026-07-15T05:00:00Z")
        let field = StarField(catalog: Self.catalog, epoch: date)
        let camera = CameraIntrinsics(longSideFieldOfViewDeg: 90, width: 1000, height: 1600)
        let projector = SkyProjector(attitude: .upright(facingAzimuth: 180, pitchDeg: 15), intrinsics: camera)
        let rotation = SkyRotation.eqjToReference(at: date, observer: Self.candlestick)
        let open = field.project(through: projector, eqjToReference: rotation, magnitudeLimit: 6.5, extinction: .typical, horizon: HorizonLookup(nil))
        let wall = field.project(through: projector, eqjToReference: rotation, magnitudeLimit: 6.5, extinction: .typical,
                                 horizon: HorizonLookup(.flat(20)))
        #expect(wall.allSatisfy { $0.altitudeDeg >= 20 })
        #expect(open.contains { $0.altitudeDeg < 20 })
        #expect(wall.count < open.count)
    }
}

func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
    let d = (a * b).sum() / ((a * a).sum() * (b * b).sum()).squareRoot()
    return acos(max(-1, min(1, d))) * 180 / .pi
}
