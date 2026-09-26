import Foundation
import Testing
@testable import SkyCore

/// Minimal PNG reader for the recorded terrarium fixture: 8-bit RGB/RGBA,
/// non-interlaced. Test-only; the app decodes tiles with ImageIO and SkyCore
/// only ever sees RGB samples.
enum FixturePNG {
    struct Failure: Error { let reason: String }

    static func rgb(_ data: Data) throws -> TerrariumTile {
        let bytes = [UInt8](data)
        guard bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { throw Failure(reason: "signature") }
        func u32(_ i: Int) -> Int { bytes[i..<i + 4].reduce(0) { $0 << 8 | Int($1) } }
        var i = 8, width = 0, height = 0, channels = 0
        var idat: [UInt8] = []
        while i + 8 <= bytes.count {
            let length = u32(i)
            let type = String(decoding: bytes[i + 4..<i + 8], as: UTF8.self)
            let body = bytes[i + 8..<i + 8 + length]
            if type == "IHDR" {
                width = u32(i + 8)
                height = u32(i + 12)
                let (depth, color, interlace) = (body[body.startIndex + 8], body[body.startIndex + 9], body[body.startIndex + 12])
                guard depth == 8, interlace == 0, color == 2 || color == 6 else { throw Failure(reason: "format") }
                channels = color == 2 ? 3 : 4
            } else if type == "IDAT" {
                idat += body
            }
            i += 12 + length
        }
        // zlib stream -> raw DEFLATE, which is what Foundation's .zlib expects.
        let deflate = Data(idat.dropFirst(2).dropLast(4))
        let raw = [UInt8](try (deflate as NSData).decompressed(using: .zlib) as Data)
        let stride = width * channels
        guard width == height, raw.count == height * (stride + 1) else { throw Failure(reason: "size") }

        var out = [UInt8](repeating: 0, count: width * height * 3)
        var prev = [UInt8](repeating: 0, count: stride)
        var cur = [UInt8](repeating: 0, count: stride)
        for y in 0..<height {
            let filter = raw[y * (stride + 1)]
            for x in 0..<stride {
                let v = raw[y * (stride + 1) + 1 + x]
                let a = x >= channels ? Int(cur[x - channels]) : 0
                let b = Int(prev[x])
                let c = x >= channels ? Int(prev[x - channels]) : 0
                let predictor: Int
                switch filter {
                case 0: predictor = 0
                case 1: predictor = a
                case 2: predictor = b
                case 3: predictor = (a + b) / 2
                case 4:
                    let p = a + b - c
                    let (pa, pb, pc) = (abs(p - a), abs(p - b), abs(p - c))
                    predictor = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
                default: throw Failure(reason: "filter \(filter)")
                }
                cur[x] = UInt8(truncatingIfNeeded: Int(v) + predictor)
            }
            for x in 0..<width {
                for k in 0..<3 { out[(y * width + x) * 3 + k] = cur[x * channels + k] }
            }
            swap(&prev, &cur)
        }
        return try TerrariumTile(size: width, rgb: out)
    }
}

/// PLAN M9's DEM check: the skyline computed on-device from AWS Terrain Tiles
/// must match the ArcGIS Skyline measurement (USGS 3DEP 10 m) within 0.5° RMS.
@Suite("Real-DEM validation: Candlestick Camp")
struct CandlestickDEMValidationTests {
    static let camp = (lat: 38.374031, lon: -109.965416)
    static let fixture = "ios/Packages/SkyCore/Tests/Fixtures/terrarium-candlestick"

    @Test("the computed skyline matches the measured one within 0.5° RMS")
    func computedMatchesMeasured() throws {
        var march = HorizonRayMarch()
        march.maxDistanceMeters = 16_000
        let ids = SlippyTiles.tilesCovering(
            latitude: Self.camp.lat, longitude: Self.camp.lon, radiusMeters: march.maxDistanceMeters, zoom: 12)
        #expect(ids.count == 25)
        var tiles: [TileID: TerrariumTile] = [:]
        for id in ids {
            tiles[id] = try FixturePNG.rgb(Repo.data("\(Self.fixture)/\(id.z)/\(id.x)/\(id.y).png"))
        }
        let sampler = TerrariumElevationSampler(zoom: 12, source: InMemoryTerrariumTiles(tiles))
        let computed = try march.profile(latitude: Self.camp.lat, longitude: Self.camp.lon, sampler: sampler)
        let measured = try HorizonProfile.bundled("candlestick-camp")

        let diffs = measured.samples.map { computed.altitudeDeg(atAzimuth: $0.azimuthDeg) - $0.altitudeDeg }
        let rms = (diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)).squareRoot()
        let bias = diffs.reduce(0, +) / Double(diffs.count)
        // 2026-09-26: RMS 0.494°, mean −0.30°. 3DEP resampled to ~30 m smooths
        // the towers near azimuth 70–75° and the ledges ~300 m north of camp.
        #expect(rms < 0.5, "RMS \(rms)°, mean \(bias)°")
    }

    @Test("the fixture decodes to plausible White Rim elevations")
    func fixtureDecodes() throws {
        let tile = try FixturePNG.rgb(Repo.data("\(Self.fixture)/12/796/1574.png"))
        let sampler = TerrariumElevationSampler(zoom: 12, source: InMemoryTerrariumTiles([TileID(z: 12, x: 796, y: 1574): tile]))
        let ground = try #require(sampler.elevationMeters(latitude: Self.camp.lat, longitude: Self.camp.lon))
        // ArcGIS put the observer at 1320.3 m on the 10 m DEM.
        #expect(abs(ground - 1320.3) < 10)
    }
}
