import Foundation
import Testing
@testable import SkyCore

/// Synthetic DEMs with analytic skylines. Elevations are defined by
/// great-circle distance from a centre, so every ray's geometry is exact.
struct RadialDEM: ElevationSampler {
    let latitude: Double
    let longitude: Double
    let elevation: @Sendable (_ distance: Double, _ bearingDeg: Double) -> Double

    func elevationMeters(latitude lat: Double, longitude lon: Double) -> Double? {
        let r = Double.pi / 180
        let (p1, p2, dl) = (latitude * r, lat * r, (lon - longitude) * r)
        let a = pow(sin((p2 - p1) / 2), 2) + cos(p1) * cos(p2) * pow(sin(dl / 2), 2)
        let d = 2 * HorizonRayMarch.earthRadiusMeters * asin(min(1, sqrt(a)))
        let bearing = atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)) / r
        return elevation(d, (bearing + 360).truncatingRemainder(dividingBy: 360))
    }
}

@Suite("Horizon ray march over synthetic DEMs")
struct HorizonRayMarchTests {
    static let lat = 38.374031
    static let lon = -109.965416

    /// Tangent-ray dip below horizontal for an eye `h` metres above a sphere of radius `re`.
    static func dip(_ h: Double, _ re: Double) -> Double { -acos(re / (re + h)) * 180 / .pi }

    @Test("a flat plain gives the curvature dip, reduced by refraction", arguments: [0.0, 0.13])
    func flatPlainDip(k: Double) throws {
        var march = HorizonRayMarch()
        march.refractionCoefficient = k
        march.eyeHeightMeters = 0
        let plain = RadialDEM(latitude: Self.lat, longitude: Self.lon) { _, _ in 0 }
        let p = try march.profile(latitude: Self.lat, longitude: Self.lon, groundElevationMeters: 100, sampler: plain)
        let expected = Self.dip(100, HorizonRayMarch.earthRadiusMeters / (1 - k))
        #expect(p.samples.count == 360)
        for s in p.samples { #expect(abs(s.altitudeDeg - expected) < 1e-4, "az \(s.azimuthDeg)") }
        // Standard refraction shrinks the dip from 0.321° to 0.299°.
        #expect(abs(expected - (k == 0 ? -0.3211 : -0.2995)) < 1e-3)
    }

    @Test("a plain seen from eye height alone dips slightly below 0°")
    func eyeLevelPlain() throws {
        let march = HorizonRayMarch()
        let plain = RadialDEM(latitude: Self.lat, longitude: Self.lon) { _, _ in 1320 }
        let p = try march.profile(latitude: Self.lat, longitude: Self.lon, sampler: plain)
        let expected = Self.dip(march.eyeHeightMeters, march.effectiveRadiusMeters)
        #expect(expected < 0 && expected > -0.05)
        #expect(p.samples.allSatisfy { abs($0.altitudeDeg - expected) < 1e-4 })
    }

    @Test("a ridge at a known distance and height, in one sector only")
    func ridge() throws {
        let march = HorizonRayMarch()
        let distances = march.sampleDistances()
        let near = try #require(distances.first { $0 >= 4700 })
        let height = 450.0
        let dem = RadialDEM(latitude: Self.lat, longitude: Self.lon) { d, bearing in
            (60...120).contains(bearing) && d >= near - 1 && d <= near + 300 ? 1320 + height : 1320
        }
        let p = try march.profile(latitude: Self.lat, longitude: Self.lon, sampler: dem)
        let eye = 1320 + march.eyeHeightMeters
        let expected = march.elevationAngleDeg(observerElevation: eye, targetElevation: 1320 + height, distance: near)
        // Small-angle check: tan θ ≈ Δh/d − d/(2 Re), about 5.45° − 0.018°
        // (the ~0.001° left over is the ground sitting 1320 m above the sphere).
        let dh = height - march.eyeHeightMeters
        #expect(abs(expected - atan(dh / near - near / (2 * march.effectiveRadiusMeters)) * 180 / .pi) < 2e-3)
        #expect(abs(p.altitudeDeg(atAzimuth: 90) - expected) < 1e-9)
        #expect(abs(p.altitudeDeg(atAzimuth: 61) - expected) < 1e-9)
        #expect(p.altitudeDeg(atAzimuth: 180) < 0)
        #expect(p.altitudeDeg(atAzimuth: 300) < 0)
    }

    @Test("a cone: the apex sets the skyline straight at it, the flanks fall away")
    func cone() throws {
        var march = HorizonRayMarch()
        march.eyeHeightMeters = 0
        let distances = march.sampleDistances()
        let apexDistance = try #require(distances.first { $0 >= 10_000 })
        let (height, baseRadius) = (500.0, 3000.0)
        let apex = HorizonRayMarch.destination(latitude: Self.lat, longitude: Self.lon, azimuthDeg: 90, distance: apexDistance)
        let fromApex = RadialDEM(latitude: apex.latitude, longitude: apex.longitude) { d, _ in
            max(0, height - height / baseRadius * d)
        }
        let p = try march.profile(latitude: Self.lat, longitude: Self.lon, groundElevationMeters: 0, sampler: fromApex)
        let atApex = march.elevationAngleDeg(observerElevation: 0, targetElevation: height, distance: apexDistance)
        #expect(abs(p.altitudeDeg(atAzimuth: 90) - atApex) < 1e-6)
        // The cone spans ±asin(3 / 10) = ±17.46° of azimuth; the skyline falls off either side.
        var previous = p.altitudeDeg(atAzimuth: 90)
        for az in 91...107 {
            let alt = p.altitudeDeg(atAzimuth: Double(az))
            #expect(alt < previous && alt > 0)
            #expect(abs(alt - p.altitudeDeg(atAzimuth: Double(180 - az))) < 0.05)
            previous = alt
        }
        #expect(p.altitudeDeg(atAzimuth: 110) < 0 && p.altitudeDeg(atAzimuth: 110) > -0.001)
    }

    @Test func missingElevationFails() {
        let holey = RadialDEM(latitude: Self.lat, longitude: Self.lon) { d, _ in d > 50_000 ? .nan : 0 }
        struct Wrapper: ElevationSampler {
            let inner: RadialDEM
            func elevationMeters(latitude: Double, longitude: Double) -> Double? {
                inner.elevationMeters(latitude: latitude, longitude: longitude).flatMap { $0.isNaN ? nil : $0 }
            }
        }
        #expect(throws: HorizonComputeError.self) {
            try HorizonRayMarch().profile(latitude: Self.lat, longitude: Self.lon, sampler: Wrapper(inner: holey))
        }
    }
}

@Suite("Terrarium tiles and slippy-map math")
struct TerrariumTests {
    @Test func terrariumDecoding() {
        #expect(Terrarium.elevationMeters(r: 128, g: 0, b: 0) == 0)
        #expect(Terrarium.elevationMeters(r: 0, g: 0, b: 0) == -32768)
        let expected: Double = 5 * 256 + 40 + 77.0 / 256
        #expect(Terrarium.elevationMeters(r: 133, g: 40, b: 77) == expected)
        for elev in [-412.5, 0, 1320.3, 4421.0] {
            let c = Terrarium.rgb(elevationMeters: elev)
            #expect(abs(Terrarium.elevationMeters(r: c.r, g: c.g, b: c.b) - elev) <= 0.5 / 256)
        }
    }

    @Test func slippyTiles() {
        #expect(SlippyTiles.tile(latitude: 0, longitude: 0, zoom: 0) == TileID(z: 0, x: 0, y: 0))
        #expect(SlippyTiles.tile(latitude: 0.001, longitude: 0.001, zoom: 1) == TileID(z: 1, x: 1, y: 0))
        #expect(SlippyTiles.tile(latitude: -0.001, longitude: -0.001, zoom: 1) == TileID(z: 1, x: 0, y: 1))
        #expect(SlippyTiles.tile(latitude: 38.374031, longitude: -109.965416, zoom: 12) == TileID(z: 12, x: 796, y: 1574))
        #expect(SlippyTiles.tile(latitude: 38.374031, longitude: -109.965416, zoom: 15) == TileID(z: 15, x: 6374, y: 12596))
        #expect(SlippyTiles.tile(latitude: 89, longitude: 180, zoom: 3) == TileID(z: 3, x: 0, y: 0))

        let t = TileID(z: 15, x: 6374, y: 12596)
        let nw = SlippyTiles.northWest(of: t)
        let se = SlippyTiles.northWest(of: TileID(z: 15, x: t.x + 1, y: t.y + 1))
        #expect(nw.latitude > 38.374031 && se.latitude < 38.374031)
        #expect(nw.longitude < -109.965416 && se.longitude > -109.965416)
        #expect(SlippyTiles.tile(latitude: nw.latitude - 1e-9, longitude: nw.longitude + 1e-9, zoom: 15) == t)
    }

    @Test func tilesCoveringARadius() {
        let tiles = SlippyTiles.tilesCovering(latitude: 38.374031, longitude: -109.965416, radiusMeters: 10_000, zoom: 12)
        // z12 tiles here are ~7.7 km square, so ±10 km spans 3–4 tiles each way.
        #expect((9...20).contains(tiles.count))
        #expect(tiles.contains(TileID(z: 12, x: 796, y: 1574)))
        #expect(Set(tiles).count == tiles.count)
        let wrapped = SlippyTiles.tilesCovering(latitude: 0, longitude: 179.99, radiusMeters: 5000, zoom: 4)
        #expect(wrapped.contains(TileID(z: 4, x: 15, y: 7)) && wrapped.contains(TileID(z: 4, x: 0, y: 8)))
    }

    @Test func rejectsWrongSampleCount() {
        #expect(throws: TerrariumTile.Error.wrongSampleCount(expected: 12, got: 11)) {
            try TerrariumTile(size: 2, rgb: Array(repeating: 0, count: 11))
        }
    }

    /// Tiles whose elevation is linear in global pixel x and y: bilinear
    /// interpolation reproduces it exactly, including across tile edges.
    struct PlaneTiles: TerrariumTileSource {
        let zoom: Int
        let size = 4
        func elevation(_ gx: Double, _ gy: Double) -> Double { 1000 + 2 * gx - 0.5 * gy }
        func tile(_ id: TileID) -> TerrariumTile? {
            guard id.z == zoom else { return nil }
            var rgb: [UInt8] = []
            for py in 0..<size {
                for px in 0..<size {
                    let c = Terrarium.rgb(elevationMeters: elevation(
                        Double(id.x * size + px) + 0.5, Double(id.y * size + py) + 0.5))
                    rgb += [c.r, c.g, c.b]
                }
            }
            return try? TerrariumTile(size: size, rgb: rgb)
        }
    }

    @Test func bilinearAcrossTileEdges() throws {
        let source = PlaneTiles(zoom: 10)
        let sampler = TerrariumElevationSampler(zoom: 10, tileSize: 4, source: source)
        for (lat, lon) in [(38.374031, -109.965416), (38.3, -110.0390625), (38.41, -109.9)] {
            let c = SlippyTiles.tileCoordinate(latitude: lat, longitude: lon, zoom: 10)
            let z = try #require(sampler.elevationMeters(latitude: lat, longitude: lon))
            #expect(abs(z - source.elevation(c.x * 4, c.y * 4)) < 1.0 / 256)
        }
        let missing = TerrariumElevationSampler(zoom: 11, tileSize: 4, source: source)
        #expect(missing.elevationMeters(latitude: 38.37, longitude: -109.96) == nil)
    }

    @Test("terrarium tiles feed the ray march end to end")
    func endToEnd() throws {
        let c = Terrarium.rgb(elevationMeters: 1320.25)
        let flat = try TerrariumTile(size: 256, rgb: Array((0..<(256 * 256)).map { _ in [c.r, c.g, c.b] }.joined()))
        var march = HorizonRayMarch()
        march.maxDistanceMeters = 20_000
        let lat = 38.374031, lon = -109.965416
        let tiles = SlippyTiles.tilesCovering(latitude: lat, longitude: lon, radiusMeters: march.maxDistanceMeters, zoom: 12)
        let source = InMemoryTerrariumTiles(Dictionary(uniqueKeysWithValues: tiles.map { ($0, flat) }))
        let p = try march.profile(latitude: lat, longitude: lon, sampler: TerrariumElevationSampler(zoom: 12, source: source))
        let expected = -acos(march.effectiveRadiusMeters / (march.effectiveRadiusMeters + march.eyeHeightMeters)) * 180 / .pi
        #expect(p.samples.allSatisfy { abs($0.altitudeDeg - expected) < 1e-4 })

        var tooFar = march
        tooFar.maxDistanceMeters = 40_000
        #expect(throws: HorizonComputeError.self) {
            try tooFar.profile(latitude: lat, longitude: lon, sampler: TerrariumElevationSampler(zoom: 12, source: source))
        }
    }
}
