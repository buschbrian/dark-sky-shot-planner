import Foundation
import Testing
@testable import SkyCore

@Suite("Airmass, extinction and sky brightness")
struct SkyBrightnessTests {
    /// Near the zenith any airmass formula is sec z; at the horizon Kasten &
    /// Young give 37.92 (their paper's value for h = 0).
    @Test("Kasten–Young airmass: sec z overhead, 37.9 at the horizon", arguments: [90.0, 75, 60, 45, 30])
    func airmass(_ alt: Double) {
        let secZ = 1 / sin(alt * .pi / 180)
        #expect(abs(Airmass.kastenYoung(altitudeDeg: alt) - secZ) / secZ < 0.003)
    }

    @Test("Kasten–Young airmass at the horizon")
    func horizonAirmass() {
        #expect(abs(Airmass.kastenYoung(altitudeDeg: 0) - 37.92) < 0.01)
        #expect(Airmass.kastenYoung(altitudeDeg: -5) == Airmass.kastenYoung(altitudeDeg: -1))
    }

    @Test("extinction: nothing at the zenith, ~0.2 mag at 30°, ~7 mag at the horizon")
    func extinction() {
        let e = Extinction.typical
        #expect(abs(e.deltaMagnitude(altitudeDeg: 90)) < 1e-12)
        #expect(abs(e.deltaMagnitude(altitudeDeg: 30) - 0.2 * 0.9946) < 0.001)
        #expect(e.deltaMagnitude(altitudeDeg: 0) > 7 && e.deltaMagnitude(altitudeDeg: 0) < 7.6)
        // Monotonic toward the horizon.
        let values = stride(from: 90.0, through: -1, by: -1).map(e.deltaMagnitude)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    static func lighting(sunAlt: Double, moonAlt: Double, phase: Double) -> SkyLighting {
        SkyLighting(
            sun: HorizontalPosition(altitudeDeg: sunAlt, azimuthDeg: 300),
            moon: HorizontalPosition(altitudeDeg: moonAlt, azimuthDeg: 120), moonPhaseAngleDeg: phase)
    }

    @Test("dark sky: ~21.9 mag/arcsec² overhead, brighter toward the horizon, NELM ~6.6")
    func darkSky() {
        let l = Self.lighting(sunAlt: -30, moonAlt: -20, phase: 0)
        let zenith = SkyBrightness.nanoLamberts(toward: HorizontalPosition(altitudeDeg: 90, azimuthDeg: 0), lighting: l)
        #expect(abs(zenith - 60) < 1e-9)
        #expect(abs(SkyBrightness.magnitudePerArcsec2(nanoLamberts: zenith) - 21.89) < 0.01)
        let low = SkyBrightness.nanoLamberts(toward: HorizontalPosition(altitudeDeg: 10, azimuthDeg: 0), lighting: l)
        #expect(low > zenith * 1.5)
        #expect(abs(SkyBrightness.zenithLimitingMagnitude(l) - 6.6) < 0.1)
    }

    /// Unihedron's table: 22.0 → 6.6, 21.0 → 6.1, 20.0 → 5.5, 18.0 → 4.0.
    @Test("naked-eye limiting magnitude from sky brightness", arguments: [(22.0, 6.6), (21.0, 6.1), (20.0, 5.5), (18.0, 4.0)])
    func nelm(_ c: (mpsas: Double, nelm: Double)) {
        #expect(abs(SkyBrightness.nakedEyeLimitingMagnitude(skyMagnitudePerArcsec2: c.mpsas) - c.nelm) < 0.1)
    }

    @Test("Krisciunas–Schaefer moonlight: brighter near the Moon, with phase, and with the Moon higher")
    func moonlight() {
        let full = Self.lighting(sunAlt: -30, moonAlt: 40, phase: 0)
        let quarter = Self.lighting(sunAlt: -30, moonAlt: 40, phase: 90)
        let near = HorizontalPosition(altitudeDeg: 45, azimuthDeg: 125)
        let far = HorizontalPosition(altitudeDeg: 45, azimuthDeg: 300)
        #expect(SkyBrightness.moonlight(toward: near, lighting: full) > SkyBrightness.moonlight(toward: far, lighting: full))
        #expect(SkyBrightness.moonlight(toward: far, lighting: full) > 2 * SkyBrightness.moonlight(toward: far, lighting: quarter))
        #expect(SkyBrightness.moonlight(toward: far, lighting: Self.lighting(sunAlt: -30, moonAlt: -5, phase: 0)) == 0)
        // A full Moon 40° up leaves ~5th-magnitude stars overhead, not 6.6.
        let nelm = SkyBrightness.zenithLimitingMagnitude(full)
        #expect(nelm > 4 && nelm < 5.7)
    }

    @Test("twilight fades out by astronomical darkness")
    func twilight() {
        let z = HorizontalPosition(altitudeDeg: 90, azimuthDeg: 0)
        func mpsas(_ h: Double) -> Double {
            SkyBrightness.magnitudePerArcsec2(nanoLamberts: SkyBrightness.nanoLamberts(toward: z, lighting: Self.lighting(sunAlt: h, moonAlt: -20, phase: 0)))
        }
        #expect(mpsas(-3) < 13)
        #expect(mpsas(-6) < 15 && mpsas(-6) > 12.5)
        #expect(mpsas(-12) < 20.5 && mpsas(-12) > 18.5)
        #expect(abs(mpsas(-18) - mpsas(-30)) < 0.05)
        #expect(abs(SkyLighting.phaseAngleDeg(illuminatedFraction: 1)) < 1e-9)
        #expect(abs(SkyLighting.phaseAngleDeg(illuminatedFraction: 0.5) - 90) < 1e-9)
    }
}

@Suite("Milky Way brightness model")
struct MilkyWayModelTests {
    typealias M = MilkyWayModel

    @Test("brightest toward Sagittarius, faint at the anticentre, dark far from the plane")
    func structure() {
        let sgr = M.brightness(l: 2.5, b: -5.5)
        #expect(sgr > 0.9)
        #expect(sgr > 4 * M.brightness(l: 180, b: 0))
        #expect(M.brightness(l: 180, b: 0) > 0.1)
        #expect(M.brightness(l: 90, b: 60) < 0.02)
        #expect(M.brightness(l: 0, b: -90) < 0.01)
    }

    @Test("Great Rift and Coalsack darken the band; the Cygnus cloud brightens it")
    func features() {
        #expect(M.brightness(l: 38, b: 2) < 0.6 * M.brightness(l: 38, b: -3))
        #expect(M.brightness(l: 301.5, b: -1) < 0.5 * M.brightness(l: 310, b: -1))
        #expect(M.brightness(l: 72, b: 3) > M.brightness(l: 120, b: 3))
        #expect(M.brightness(l: 27, b: -3) > M.brightness(l: 50, b: -3))
    }

    @Test("wraps across l = 0 and is deterministic")
    func wrap() {
        #expect(abs(M.brightness(l: -10, b: 1) - M.brightness(l: 350, b: 1)) < 1e-12)
        #expect(M.wrapped(190) == -170 && M.wrapped(-190) == 170 && M.wrapped(0) == 0)
        let params = M.shaderParameters
        #expect(params.count == 1 + 5 * (M.starClouds.count + M.dustClouds.count))
        #expect(Int(params[0]) == M.starClouds.count)
    }

    @Test("the GC direction through astronomy-engine's rotation is l = 0, b = 0")
    func galacticFrame() {
        // Planner's GC J2000 position.
        let gc = SkyRotation.vector(raDeg: 266.405, decDeg: -28.936)
        let g = SkyRotation.galacticToEQJ.transposed * gc
        let lb = M.galactic(g)
        #expect(min(lb.l, 360 - lb.l) < 0.1 && abs(lb.b) < 0.1)
    }
}

@Suite("Star-trail design")
struct StarTrailsTests {
    static let candlestick = try! Observer(latitude: 38.374031, longitude: -109.965416)

    @Test("trail arc: 15.04° an hour, gaps and frame counts from the sequence")
    func arc() throws {
        let start = try ISO.date("2026-07-15T04:00:00Z")
        let hour = try StarTrailSequence(start: start, exposure: 30, interval: 30, frames: 120)
        #expect(hour.duration == 3600)
        #expect(abs(hour.arcDeg - 15.0411) < 0.0005)
        #expect(hour.gapFraction == 0)
        let gappy = try StarTrailSequence(start: start, duration: 7200, exposure: 25, interval: 30)
        #expect(gappy.frames == 240)
        #expect(abs(gappy.gapFraction - 1.0 / 6) < 1e-12)
        #expect(abs(gappy.arcDeg - 7195 * 360 / 86164.0905) < 1e-9)
        let plan = try Timelapse.plan(exposure: 20, interval: 25, fps: 24, clipSeconds: 10)
        let fromTimelapse = try StarTrailSequence(start: start, timelapse: plan)
        #expect(fromTimelapse.frames == 240 && fromTimelapse.interval == 25)
        #expect(throws: ExposureError.self) { try StarTrailSequence(start: start, exposure: 30, interval: 20, frames: 10) }
    }

    @Test("30, 60 and 120 min designs: arc length and the pole over Candlestick Camp", arguments: [
        (30, 7.5205), (60, 15.0411), (120, 30.0821),
    ])
    func designs(_ c: (minutes: Int, arcDeg: Double)) throws {
        let start = try ISO.date("2026-07-15T04:30:00Z")
        let seq = try StarTrailSequence(start: start, exposure: 30, interval: 30, frames: c.minutes * 2)
        #expect(seq.duration == Double(c.minutes * 60))
        #expect(abs(seq.arcDeg - c.arcDeg) < 0.0005)
        let field = StarField(catalog: StarCatalogTests.catalog, epoch: start)
        let preview = StarTrailPreview(sequence: seq, field: field, observer: Self.candlestick, magnitudeLimit: 2)
        #expect(abs(preview.pole.altitudeDeg - 38.395) < 0.01 && azimuthDelta(preview.pole.azimuthDeg, 0) < 0.01)
        // Each arc spans the sequence: Arcturus turns by the arc length about the pole.
        let arcturus = try #require(preview.arcs.first { $0.index == StarCatalogTests.catalog.index(ofHR: 5340) })
        let p = preview.pole.referenceVector
        func perp(_ v: SIMD3<Double>) -> SIMD3<Double> { v - p * (v * p).sum() }
        #expect(abs(angle(perp(arcturus.points.first!), perp(arcturus.points.last!)) - c.arcDeg) < 0.1)
    }

    @Test("the celestial pole stands at the latitude (plus refraction) due north")
    func pole() throws {
        let date = try ISO.date("2026-07-15T05:00:00Z")
        let p = StarTrails.pole(at: date, observer: Self.candlestick)
        // Refraction at 38.4° is ~1.2′; nutation and polar motion are ignored at this level.
        #expect(abs(p.altitudeDeg - (38.374031 + 0.0205)) < 0.01)
        #expect(azimuthDelta(p.azimuthDeg, 0) < 0.01)
        let south = StarTrails.pole(at: date, observer: try Observer(latitude: -30, longitude: 20))
        #expect(abs(south.altitudeDeg - 30.03) < 0.02 && azimuthDelta(south.azimuthDeg, 180) < 0.01)
    }

    @Test("Polaris is ~0.63° from the true pole in 2026 (astronomy-engine: 90° − 89.3707°)")
    func polaris() throws {
        let date = try ISO.date("2026-07-15T05:00:00Z")
        let catalog = StarCatalogTests.catalog
        let field = StarField(catalog: catalog, epoch: date)
        let d = StarTrails.distanceFromPoleDeg(ofStarAt: catalog.index(ofHR: 424)!, in: field, at: date)
        #expect(abs(d - (90 - 89.37073)) < 0.002)
    }

    @Test("stars turn about the pole: every arc point keeps its distance from the pole")
    func arcsCircleThePole() throws {
        let start = try ISO.date("2026-07-15T04:00:00Z")
        let seq = try StarTrailSequence(start: start, exposure: 30, interval: 30, frames: 240)
        let field = StarField(catalog: StarCatalogTests.catalog, epoch: start)
        let preview = StarTrailPreview(sequence: seq, field: field, observer: Self.candlestick, magnitudeLimit: 2.5)
        #expect(preview.arcs.count > 10)
        let pole = preview.pole.referenceVector
        for arc in preview.arcs {
            // Refraction bends low arcs, so compare only points well above the horizon.
            let high = arc.points.filter { $0.z > sin(20 * .pi / 180) }
            guard let first = high.first else { continue }
            for p in high { #expect(abs(angle(p, pole) - angle(first, pole)) < 0.1) }
        }
        // End-to-end turn of a star far from the pole ≈ the arc length.
        let vega = try #require(preview.arcs.first { $0.index == StarCatalogTests.catalog.index(ofHR: 7001) })
        let sweep = angle(vega.points.first! - pole * (vega.points.first! * pole).sum(), vega.points.last! - pole * (vega.points.last! * pole).sum())
        #expect(abs(sweep - seq.arcDeg) < 0.2)
    }

    @Test("pole framing: centred, outside and behind")
    func framing() throws {
        let camera = CameraIntrinsics(longSideFieldOfViewDeg: 90, width: 1000, height: 2000)
        let pole = HorizontalPosition(altitudeDeg: 38.4, azimuthDeg: 0)
        let centred = SkyProjector(attitude: .upright(facingAzimuth: 0, pitchDeg: 38.4), intrinsics: camera)
        guard case .inFrame(let x, let y) = StarTrails.framing(of: pole, projector: centred) else { Issue.record("not in frame"); return }
        #expect(abs(x - 0.5) < 1e-6 && abs(y - 0.5) < 1e-6)
        let east = SkyProjector(attitude: .upright(facingAzimuth: 60, pitchDeg: 38.4), intrinsics: camera)
        guard case .outsideFrame(let dir) = StarTrails.framing(of: pole, projector: east) else { Issue.record("not outside"); return }
        #expect(cos(dir) < -0.8) // turn left
        let south = SkyProjector(attitude: .upright(facingAzimuth: 180, pitchDeg: 10), intrinsics: camera)
        guard case .behindCamera = StarTrails.framing(of: pole, projector: south) else { Issue.record("not behind"); return }
    }
}

@Suite("Meteor radiants and find guidance")
struct SkyRadiantTests {
    static let candlestick = try! Observer(latitude: 38.374031, longitude: -109.965416)

    static func perseids() throws -> SkyRadiant {
        SkyRadiant(
            id: "PER", name: "Perseids", raDeg: 48, decDeg: 58,
            activeFrom: try ISO.date("2026-07-17T00:00:00Z"), activeUntil: try ISO.date("2026-08-24T00:00:00Z"),
            peak: try ISO.date("2026-08-13T01:00:00Z"), zhr: 100, populationIndex: 2.2,
            driftRADegPerDay: 1.35, driftDecDegPerDay: 0.12)
    }

    @Test("active window, drift from the peak, and provider filtering")
    func activity() throws {
        let per = try Self.perseids()
        #expect(per.isActive(at: try ISO.date("2026-08-12T00:00:00Z")))
        #expect(!per.isActive(at: try ISO.date("2026-09-01T00:00:00Z")))
        let eq = per.equatorial(at: try ISO.date("2026-08-15T01:00:00Z"))
        #expect(abs(eq.raDeg - 50.7) < 1e-9 && abs(eq.decDeg - 58.24) < 1e-9)
        let provider = StaticRadiants([per])
        #expect(provider.radiants(activeAt: try ISO.date("2026-08-12T00:00:00Z")).count == 1)
        #expect(provider.radiants(activeAt: try ISO.date("2026-10-12T00:00:00Z")).isEmpty)
    }

    @Test("IMO hourly rate: ZHR × sin h, fewer under brighter skies, none below the horizon")
    func rate() throws {
        let per = try Self.perseids()
        #expect(abs(MeteorRadiants.hourlyRate(radiant: per, radiantAltitudeDeg: 30)! - 50) < 1e-9)
        #expect(abs(MeteorRadiants.hourlyRate(radiant: per, radiantAltitudeDeg: 90, limitingMagnitude: 5.5)! - 100 / 2.2) < 1e-9)
        #expect(MeteorRadiants.hourlyRate(radiant: per, radiantAltitudeDeg: -5) == 0)
        let noZHR = SkyRadiant(id: "X", name: "X", raDeg: 0, decDeg: 0, activeFrom: .distantPast, activeUntil: .distantFuture)
        #expect(MeteorRadiants.hourlyRate(radiant: noZHR, radiantAltitudeDeg: 30) == nil)
    }

    @Test("radiant position and direction hints point away from it")
    func hints() throws {
        let date = try ISO.date("2026-08-13T09:00:00Z") // 03:00 MDT: LST ≈ 23.1 h, hour angle −4.1 h, so ~46° up in the NE
        let per = try Self.perseids()
        let pos = MeteorRadiants.position(of: per, at: date, observer: Self.candlestick)
        #expect(pos.altitudeDeg > 40 && pos.altitudeDeg < 55 && pos.azimuthDeg > 10 && pos.azimuthDeg < 70, "\(pos)")
        let r = pos.referenceVector
        let hints = MeteorRadiants.directionHints(radiant: r, count: 8, from: 12, to: 30)
        #expect(hints.count == 8)
        for h in hints {
            #expect(abs(angle(h.first!, r) - 12) < 1e-6 && abs(angle(h.last!, r) - 30) < 1e-6)
        }
        // The first hint heads for the zenith.
        #expect(hints[0].last!.z > r.z)
    }

    @Test("find guidance: turn and tilt toward the target, centred on it")
    func guidance() {
        let camera = CameraIntrinsics(longSideFieldOfViewDeg: 68, width: 1000, height: 1800)
        let facingSouth = SkyProjector(attitude: .upright(facingAzimuth: 180, pitchDeg: 20), intrinsics: camera)
        let west = SkyGuidance(target: HorizontalPosition(altitudeDeg: 30, azimuthDeg: 260), projector: facingSouth)
        #expect(abs(west.turnDeg - 80) < 1e-6 && abs(west.tiltDeg - 10) < 1e-6)
        #expect(!west.isOnScreen)
        #expect(west.spoken == "turn right 80°, tilt up 10°")
        let east = SkyGuidance(target: HorizontalPosition(altitudeDeg: 20, azimuthDeg: 150), projector: facingSouth)
        #expect(east.spoken == "turn left 30°")
        let there = SkyGuidance(target: HorizontalPosition(altitudeDeg: 21, azimuthDeg: 181), projector: facingSouth)
        #expect(there.spoken == "centred" && there.isOnScreen)
        let near = SkyGuidance(target: HorizontalPosition(altitudeDeg: 30, azimuthDeg: 180), projector: facingSouth)
        #expect(near.spoken == "in view, tilt up 10°")
    }
}
