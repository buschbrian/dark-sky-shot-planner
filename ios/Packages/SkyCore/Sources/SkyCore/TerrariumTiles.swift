import Foundation

/// A Web-Mercator ("slippy map") tile address.
public struct TileID: Sendable, Hashable, Codable {
    public let z: Int
    public let x: Int
    public let y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }
}

public enum SlippyTiles {
    /// AWS Terrain Tiles are used at z ≤ 15 (PLAN §Data sources).
    public static let maxZoom = 15
    public static let maxLatitude = 85.05112877980659

    /// Fractional tile coordinates of a point: the integer part is the tile,
    /// the fraction the position within it.
    public static func tileCoordinate(latitude: Double, longitude: Double, zoom: Int) -> (x: Double, y: Double) {
        precondition((0...maxZoom).contains(zoom), "zoom \(zoom) outside 0...\(maxZoom)")
        let n = Double(1 << zoom)
        let lat = min(max(latitude, -maxLatitude), maxLatitude) * .pi / 180
        let x = (longitude + 180) / 360 * n
        let y = (1 - asinh(tan(lat)) / .pi) / 2 * n
        return (x, y)
    }

    public static func tile(latitude: Double, longitude: Double, zoom: Int) -> TileID {
        let n = 1 << zoom
        let c = tileCoordinate(latitude: latitude, longitude: longitude, zoom: zoom)
        let x = (Int(c.x.rounded(.down)) % n + n) % n
        let y = min(max(Int(c.y.rounded(.down)), 0), n - 1)
        return TileID(z: zoom, x: x, y: y)
    }

    /// Latitude/longitude of a tile's north-west corner.
    public static func northWest(of tile: TileID) -> (latitude: Double, longitude: Double) {
        let n = Double(1 << tile.z)
        let lon = Double(tile.x) / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * Double(tile.y) / n))) * 180 / .pi
        return (lat, lon)
    }

    /// Every tile a ray march of `radiusMeters` around a point can touch
    /// (with a one-pixel margin for bilinear sampling at 256 px), for fetching
    /// and caching before `HorizonRayMarch` runs.
    public static func tilesCovering(
        latitude: Double, longitude: Double, radiusMeters: Double, zoom: Int
    ) -> [TileID] {
        let n = 1 << zoom
        let dLat = radiusMeters / HorizonRayMarch.earthRadiusMeters * 180 / .pi
        let dLon = dLat / max(cos(min(abs(latitude) + dLat, 89.9) * .pi / 180), 1e-6)
        let nw = tileCoordinate(latitude: latitude + dLat, longitude: longitude - dLon, zoom: zoom)
        let se = tileCoordinate(latitude: latitude - dLat, longitude: longitude + dLon, zoom: zoom)
        let margin = 1.0 / 256
        let x0 = Int((nw.x - margin).rounded(.down)), x1 = Int((se.x + margin).rounded(.down))
        let y0 = max(0, Int((nw.y - margin).rounded(.down))), y1 = min(n - 1, Int((se.y + margin).rounded(.down)))
        var out: [TileID] = []
        for y in y0...y1 {
            for x in x0...min(x1, x0 + n - 1) { out.append(TileID(z: zoom, x: (x % n + n) % n, y: y)) }
        }
        return out
    }
}

/// Mapzen/AWS "terrarium" elevation encoding.
public enum Terrarium {
    /// `elev = R·256 + G + B/256 − 32768`, metres.
    public static func elevationMeters(r: UInt8, g: UInt8, b: UInt8) -> Double {
        Double(r) * 256 + Double(g) + Double(b) / 256 - 32768
    }

    /// Inverse of `elevationMeters`, to 1/256 m (for synthetic tiles and fixtures).
    public static func rgb(elevationMeters: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let v = min(max(((elevationMeters + 32768) * 256).rounded(), 0), 16_777_215)
        let i = Int(v)
        return (UInt8(i >> 16), UInt8((i >> 8) & 0xFF), UInt8(i & 0xFF))
    }
}

/// One decoded terrarium tile: `size`×`size` pixels, row-major from the
/// north-west corner, 3 bytes (R, G, B) per pixel. PNG decoding happens
/// outside SkyCore (ImageIO in the app); SkyCore only sees the samples.
public struct TerrariumTile: Sendable, Hashable {
    public enum Error: Swift.Error, Sendable, Hashable {
        case wrongSampleCount(expected: Int, got: Int)
    }

    public let size: Int
    public let rgb: [UInt8]

    public init(size: Int, rgb: [UInt8]) throws(Error) {
        guard size > 0, rgb.count == size * size * 3 else {
            throw .wrongSampleCount(expected: max(size, 0) * max(size, 0) * 3, got: rgb.count)
        }
        self.size = size
        self.rgb = rgb
    }

    public func elevationMeters(px: Int, py: Int) -> Double {
        let i = (py * size + px) * 3
        return Terrarium.elevationMeters(r: rgb[i], g: rgb[i + 1], b: rgb[i + 2])
    }
}

/// Supplies decoded tiles; nil when a tile is unavailable (not fetched).
public protocol TerrariumTileSource {
    func tile(_ id: TileID) -> TerrariumTile?
}

public struct InMemoryTerrariumTiles: TerrariumTileSource, Sendable {
    public var tiles: [TileID: TerrariumTile]

    public init(_ tiles: [TileID: TerrariumTile] = [:]) { self.tiles = tiles }

    public func tile(_ id: TileID) -> TerrariumTile? { tiles[id] }
}

/// Bilinear elevation over terrarium tiles at one zoom, interpolating across
/// tile edges. Pixel values are taken at pixel centres.
public struct TerrariumElevationSampler<Source: TerrariumTileSource>: ElevationSampler {
    public let zoom: Int
    public let tileSize: Int
    public let source: Source

    public init(zoom: Int, tileSize: Int = 256, source: Source) {
        precondition((0...SlippyTiles.maxZoom).contains(zoom), "zoom \(zoom) outside 0...\(SlippyTiles.maxZoom)")
        self.zoom = zoom
        self.tileSize = tileSize
        self.source = source
    }

    /// Elevation of the pixel at global pixel coordinates (wrapping in x).
    func pixel(_ gx: Int, _ gy: Int) -> Double? {
        let n = 1 << zoom
        let world = n * tileSize
        let x = (gx % world + world) % world
        let y = min(max(gy, 0), world - 1)
        guard let t = source.tile(TileID(z: zoom, x: x / tileSize, y: y / tileSize)), t.size == tileSize else { return nil }
        return t.elevationMeters(px: x % tileSize, py: y % tileSize)
    }

    public func elevationMeters(latitude: Double, longitude: Double) -> Double? {
        let c = SlippyTiles.tileCoordinate(latitude: latitude, longitude: longitude, zoom: zoom)
        let u = c.x * Double(tileSize) - 0.5
        let v = c.y * Double(tileSize) - 0.5
        let i = Int(u.rounded(.down))
        let j = Int(v.rounded(.down))
        let fx = u - Double(i)
        let fy = v - Double(j)
        guard let z00 = pixel(i, j), let z10 = pixel(i + 1, j),
              let z01 = pixel(i, j + 1), let z11 = pixel(i + 1, j + 1) else { return nil }
        let top = z00 + (z10 - z00) * fx
        let bottom = z01 + (z11 - z01) * fx
        return top + (bottom - top) * fy
    }
}
