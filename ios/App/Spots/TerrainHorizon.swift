import Accelerate
import Foundation
import ImageIO
import SkyCore

/// M9 on device: fetch AWS Terrain Tiles (terrarium PNG, keyless), decode
/// them with ImageIO into the RGB samples SkyCore expects, and ray-march 360
/// azimuths with `HorizonRayMarch`. Same zoom and range as SkyCore's
/// Candlestick DEM validation, so the two can be compared.
nonisolated enum TerrainHorizon {
    static let zoom = 12
    static let marchRadiusMeters = 16_000.0
    static let tileTemplate = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
    static let attribution = "Terrain tiles by Mapzen on the AWS Open Data Registry. 3DEP, SRTM and GMTED2010 terrain data courtesy of the U.S. Geological Survey."
    static let attributionURL = URL(string: "https://github.com/tilezen/joerd/blob/master/docs/attribution.md")!
    static let maxConcurrentDownloads = 6

    enum Phase: Sendable, Equatable {
        case downloading(done: Int, total: Int)
        case tracing(done: Int, total: Int)

        var fraction: Double {
            switch self {
            case .downloading(let d, let t): t == 0 ? 0 : 0.5 * Double(d) / Double(t)
            case .tracing(let d, let t): t == 0 ? 0.5 : 0.5 + 0.5 * Double(d) / Double(t)
            }
        }

        var label: String {
            switch self {
            case .downloading(let d, let t): "Downloading terrain tiles \(d)/\(t)"
            case .tracing(let d, let t): "Tracing the skyline \(Int((Double(d) / Double(max(t, 1)) * 100).rounded())) %"
            }
        }
    }

    enum Failure: Error, LocalizedError {
        case download(TileID, String)
        case decode(TileID)
        case missingElevation

        var errorDescription: String? {
            switch self {
            case .download(let id, let why): "Tile \(id.z)/\(id.x)/\(id.y) unavailable: \(why)"
            case .decode(let id): "Tile \(id.z)/\(id.x)/\(id.y) could not be decoded"
            case .missingElevation: "Terrain unavailable for part of the 16 km range"
            }
        }
    }

    struct Output: Sendable {
        let profile: HorizonProfile
        let tileCount: Int
        let downloaded: Int
        /// Wall-clock seconds for fetch + decode, and for the ray march.
        let loadSeconds: Double
        let traceSeconds: Double
    }

    /// Tiles around the spot's 0.05° cell centre with a margin that covers any
    /// point in the cell, so the tile addresses AWS sees reveal no more than
    /// the rounded cell the Worker gets (ADR-0010).
    static func tileIDs(latitude: Double, longitude: Double) -> [TileID] {
        let lat = (latitude / 0.05).rounded() * 0.05
        let lon = (longitude / 0.05).rounded() * 0.05
        return SlippyTiles.tilesCovering(latitude: lat, longitude: lon, radiusMeters: marchRadiusMeters + 4_000, zoom: zoom)
    }

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("terrarium", isDirectory: true)
    }

    static var march: HorizonRayMarch {
        var m = HorizonRayMarch()
        m.maxDistanceMeters = marchRadiusMeters
        return m
    }

    @concurrent
    static func compute(
        latitude: Double, longitude: Double, progress: @escaping @Sendable (Phase) -> Void
    ) async throws -> Output {
        let clock = ContinuousClock()
        let t0 = clock.now
        let ids = tileIDs(latitude: latitude, longitude: longitude)
        progress(.downloading(done: 0, total: ids.count))
        var tiles: [TileID: TerrariumTile] = [:]
        var downloaded = 0
        // Fetch and decode in parallel, a bounded number at a time.
        try await withThrowingTaskGroup(of: (TileID, TerrariumTile, Bool).self) { group in
            var next = 0
            func enqueue() {
                guard next < ids.count else { return }
                let id = ids[next]
                next += 1
                group.addTask { try await load(id) }
            }
            for _ in 0..<min(maxConcurrentDownloads, ids.count) { enqueue() }
            for try await (id, tile, fetched) in group {
                tiles[id] = tile
                if fetched { downloaded += 1 }
                progress(.downloading(done: tiles.count, total: ids.count))
                try Task.checkCancellation()
                enqueue()
            }
        }
        let t1 = clock.now
        let profile = try await trace(latitude: latitude, longitude: longitude, tiles: tiles, progress: progress)
        let t2 = clock.now
        return Output(profile: profile, tileCount: ids.count, downloaded: downloaded,
                      loadSeconds: (t1 - t0).seconds, traceSeconds: (t2 - t1).seconds)
    }

    /// `HorizonRayMarch.profile`, with azimuths split across cores. Each
    /// azimuth runs exactly SkyCore's per-ray arithmetic (its public
    /// `destination` and `elevationAngleDeg` over the same distances), so the
    /// result equals the serial march bit for bit.
    @concurrent
    static func trace(
        latitude: Double, longitude: Double, tiles: [TileID: TerrariumTile],
        march: HorizonRayMarch = march, progress: @escaping @Sendable (Phase) -> Void = { _ in }
    ) async throws -> HorizonProfile {
        let source = InMemoryTerrariumTiles(tiles)
        guard let ground = TerrariumElevationSampler(zoom: zoom, source: source)
            .elevationMeters(latitude: latitude, longitude: longitude) else { throw Failure.missingElevation }
        let eye = ground + march.eyeHeightMeters
        let distances = sampleDistances(march)
        let count = march.azimuthCount
        let chunk = 8
        let chunks = stride(from: 0, to: count, by: chunk).map { $0..<min($0 + chunk, count) }
        let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
        var angles = [Double](repeating: 0, count: count)
        var done = 0
        progress(.tracing(done: 0, total: count))
        try await withThrowingTaskGroup(of: [(Int, Double)].self) { group in
            var next = 0
            func enqueue() {
                guard next < chunks.count else { return }
                let range = chunks[next]
                next += 1
                group.addTask {
                    let sampler = TerrariumElevationSampler(zoom: zoom, source: source)
                    var out: [(Int, Double)] = []
                    out.reserveCapacity(range.count)
                    for i in range {
                        try Task.checkCancellation()
                        let az = 360 * Double(i) / Double(count)
                        var best = -Double.infinity
                        for d in distances {
                            let p = HorizonRayMarch.destination(latitude: latitude, longitude: longitude, azimuthDeg: az, distance: d)
                            guard let z = sampler.elevationMeters(latitude: p.latitude, longitude: p.longitude) else {
                                throw Failure.missingElevation
                            }
                            best = max(best, march.elevationAngleDeg(observerElevation: eye, targetElevation: z, distance: d))
                        }
                        out.append((i, best))
                    }
                    return out
                }
            }
            for _ in 0..<min(width, chunks.count) { enqueue() }
            for try await part in group {
                for (i, a) in part { angles[i] = a }
                done += part.count
                progress(.tracing(done: done, total: count))
                enqueue()
            }
        }
        return try HorizonProfile(samples: angles.enumerated().map {
            HorizonProfile.Sample(azimuthDeg: 360 * Double($0.offset) / Double(count), altitudeDeg: $0.element)
        })
    }

    /// `HorizonRayMarch.sampleDistances()` is internal to SkyCore; same loop.
    static func sampleDistances(_ m: HorizonRayMarch) -> [Double] {
        var out: [Double] = []
        var d = m.minDistanceMeters
        while d <= m.maxDistanceMeters {
            out.append(d)
            d += max(m.minStepMeters, d * m.stepGrowth)
        }
        return out
    }

    /// From the on-disk cache when present (so a recompute works offline), else AWS.
    static func load(_ id: TileID) async throws -> (TileID, TerrariumTile, Bool) {
        let file = cacheDirectory.appendingPathComponent("\(id.z)/\(id.x)/\(id.y).png")
        if let data = try? Data(contentsOf: file), let tile = try? decode(data) {
            return (id, tile, false)
        }
        let url = URL(string: String(format: tileTemplate, id.z, id.x, id.y))!
        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Failure.download(id, "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            data = body
        } catch let error as Failure {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.download(id, (error as? URLError)?.code == .notConnectedToInternet ? "offline" : error.localizedDescription)
        }
        guard let tile = try? decode(data) else { throw Failure.decode(id) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return (id, tile, true)
    }

    /// PNG → RGB bytes without colour management: terrarium pixels are
    /// numbers, so any conversion would corrupt the elevations.
    static func decode(_ data: Data) throws -> TerrariumTile {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              image.width == image.height, image.bitsPerComponent == 8,
              image.colorSpace?.model == .rgb || image.colorSpace == nil
        else { throw Failure.decode(TileID(z: 0, x: 0, y: 0)) }
        let size = image.width
        let bytesPerPixel = image.bitsPerPixel / 8
        let offsets: (r: Int, g: Int, b: Int)
        switch bytesPerPixel {
        case 3:
            offsets = (0, 1, 2)
        case 4:
            let alphaFirst = [.first, .premultipliedFirst, .noneSkipFirst].contains(image.alphaInfo)
            let little = image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little
            switch (alphaFirst, little) {
            case (false, false): offsets = (0, 1, 2) // RGBA
            case (true, false): offsets = (1, 2, 3) // ARGB
            case (false, true): offsets = (3, 2, 1) // ABGR in memory
            case (true, true): offsets = (2, 1, 0) // BGRA in memory
            }
        default:
            throw Failure.decode(TileID(z: 0, x: 0, y: 0))
        }
        guard let cf = image.dataProvider?.data else { throw Failure.decode(TileID(z: 0, x: 0, y: 0)) }
        let raw = cf as Data
        let rowBytes = image.bytesPerRow
        guard raw.count >= rowBytes * (size - 1) + size * bytesPerPixel else { throw Failure.decode(TileID(z: 0, x: 0, y: 0)) }
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        if bytesPerPixel == 4, offsets == (0, 1, 2) {
            // ImageIO's usual layout for these PNGs (RGBX): one vImage pass.
            let ok = raw.withUnsafeBytes { src in
                rgb.withUnsafeMutableBytes { dst in
                    var s = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src.baseAddress!), height: vImagePixelCount(size),
                                          width: vImagePixelCount(size), rowBytes: rowBytes)
                    var d = vImage_Buffer(data: dst.baseAddress!, height: vImagePixelCount(size),
                                          width: vImagePixelCount(size), rowBytes: size * 3)
                    return vImageConvert_RGBA8888toRGB888(&s, &d, vImage_Flags(kvImageNoFlags)) == kvImageNoError
                }
            }
            if ok { return try TerrariumTile(size: size, rgb: rgb) }
        }
        raw.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for y in 0..<size {
                let row = y * rowBytes
                for x in 0..<size {
                    let p = row + x * bytesPerPixel
                    let o = (y * size + x) * 3
                    rgb[o] = buf[p + offsets.r]
                    rgb[o + 1] = buf[p + offsets.g]
                    rgb[o + 2] = buf[p + offsets.b]
                }
            }
        }
        return try TerrariumTile(size: size, rgb: rgb)
    }
}

/// Candlestick Camp's measured skyline (`config/horizon-profiles/candlestick-camp.csv`),
/// offered for spots at the camp and used to check a computed profile.
nonisolated enum MeasuredHorizons {
    static let candlestick = (latitude: 38.374031, longitude: -109.965416)
    static let candlestickSource = "Measured: ArcGIS Pro Skyline on USGS 3DEP 10 m, 2026-09-04 (config/horizon-profiles/candlestick-camp.csv)"
    static let nearMeters = 1_000.0

    static func isAtCandlestick(latitude: Double, longitude: Double) -> Bool {
        guard let d = Geodesy.inverse(
            from: GeoCoordinate(latitude: latitude, longitude: longitude),
            to: GeoCoordinate(latitude: candlestick.latitude, longitude: candlestick.longitude)) else { return false }
        return d.distanceMeters < nearMeters
    }

    static func candlestickProfile() -> HorizonProfile? { try? HorizonProfile.bundled("candlestick-camp") }

    /// RMS and mean of computed − measured over the measured azimuths.
    static func compare(_ computed: HorizonProfile, to measured: HorizonProfile) -> (rms: Double, mean: Double) {
        let diffs = measured.samples.map { computed.altitudeDeg(atAzimuth: $0.azimuthDeg) - $0.altitudeDeg }
        let rms = (diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)).squareRoot()
        return (rms, diffs.reduce(0, +) / Double(diffs.count))
    }
}

nonisolated extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) * 1e-18 }
}
