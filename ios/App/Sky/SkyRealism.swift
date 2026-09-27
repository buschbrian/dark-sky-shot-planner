import SkyCore
import SwiftUI

/// Layer switches for the Sky view.
struct SkyLayers: Equatable {
    var stars = true
    var constellationLines = true
    var names = true
    var milkyWay = true
    /// Live only: draw the simulated sky instead of the camera picture.
    var planetarium = false
}

/// Something the "find" flow can point the phone at.
enum SkyFindTarget: Hashable {
    case constellation(String)
    case star(hr: Int)
    case body(SkyObject)
    case radiant(id: String)
}

/// The night's stars, computed off the main actor with the rest of `SkyModel`.
nonisolated struct SkyStars: Sendable {
    let field: StarField
    /// Colour bucket per catalogue star (`SkyStarColors`).
    let colorBucket: [UInt8]
    /// J2000 centre of each constellation figure, by abbreviation.
    let centres: [String: SIMD3<Double>]

    static func compute(epoch: Date) -> SkyStars? {
        guard let catalog = try? StarCatalog.bundled() else { return nil }
        let field = StarField(catalog: catalog, epoch: epoch)
        return SkyStars(
            field: field, colorBucket: catalog.stars.map { SkyStarColors.bucket(bv: $0.bv) },
            centres: Dictionary(uniqueKeysWithValues: catalog.constellations.map { ($0.abbreviation, field.centre(of: $0)) }))
    }

    var catalog: StarCatalog { field.catalog }
}

/// Approximate blackbody colours by B−V, desaturated the way the eye sees
/// stars: blue-white hot stars to orange cool ones. Standard mode only.
nonisolated enum SkyStarColors {
    static let rgb: [(Double, Double, Double)] = [
        (0.66, 0.76, 1.00), // B−V < −0.1
        (0.82, 0.88, 1.00), // < 0.15
        (0.97, 0.97, 1.00), // < 0.45
        (1.00, 0.96, 0.88), // < 0.8
        (1.00, 0.88, 0.70), // < 1.2
        (1.00, 0.78, 0.55), // < 1.6
        (1.00, 0.68, 0.42), // redder
    ]

    static func bucket(bv: Double?) -> UInt8 {
        guard let bv else { return 2 }
        let edges = [-0.1, 0.15, 0.45, 0.8, 1.2, 1.6]
        return UInt8(edges.firstIndex { bv < $0 } ?? edges.count)
    }
}

/// A star-trail design the Sky view previews and the capture flow can run.
/// Saved (UserDefaults `sky.trailDesign`) whenever it changes in the Sky view.
struct SkyTrailDesign: Codable, Equatable {
    var sequence: StarTrailSequence
    /// Where the celestial pole sat in the view when last previewed
    /// (fractions of width and height), nil when outside it.
    var poleInFrame: CGPoint?

    static let key = "sky.trailDesign"

    static var saved: SkyTrailDesign? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SkyTrailDesign.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Radiants for the Sky view, supplied by the sky-events code:
/// `.environment(\.skyRadiants, provider)` on the Sky tab.
extension EnvironmentValues {
    @Entry var skyRadiants: (any SkyRadiantProviding)? = nil
}

/// Everything the star layer draws for one frame, in view points.
struct SkyRealismFrame {
    struct Star {
        let point: CGPoint
        let magnitude: Double
        let color: UInt8
    }

    struct Label {
        let text: String
        let point: CGPoint
        let isConstellation: Bool
        let highlighted: Bool
    }

    struct Radiant {
        let name: String
        let point: CGPoint?
        let position: HorizontalPosition
        let hints: [[CGPoint]]
        let hourlyRate: Double?
    }

    struct Trails {
        let runs: [(runs: [[CGPoint]], magnitude: Double, color: UInt8)]
        let pole: CGPoint?
        let polaris: CGPoint?
        let polarisOffsetDeg: Double?
        let framing: PoleFraming
        let sequence: StarTrailSequence
    }

    struct Find {
        let name: String
        let guidance: SkyGuidance
        let point: CGPoint?
    }

    var stars: [Star] = []
    var limitingMagnitude = 6.5
    var starScale = 1.0
    var figures: [(abbreviation: String, runs: [[CGPoint]], highlighted: Bool)] = []
    var labels: [Label] = []
    var trails: Trails?
    var radiants: [Radiant] = []
    var find: Find?
    /// Constellation names whose centre is on screen, for VoiceOver.
    var constellationsOnScreen: [String] = []
    var namedStarsOnScreen: [String] = []
}

/// Per-frame inputs that change slowly, cached so a frame costs little.
final class SkyRealismCache {
    private var sunKey: (Date, Double, Double)?
    private var sunValue = HorizontalPosition(altitudeDeg: -30, azimuthDeg: 0)
    private var trailKey: (StarTrailSequence, Double, Double, Double)?
    private var trailValue: StarTrailPreview?
    private var polarisOffset: Double?
    private var lookupKey: HorizonProfile??
    private var lookupValue = HorizonLookup(nil)
    private var terrainKey: HorizonProfile??
    private var terrainValue: [Float] = [0]

    /// The skyline per half degree for per-star tests (flat without a profile).
    func horizonLookup(_ profile: HorizonProfile?) -> HorizonLookup {
        if let lookupKey, lookupKey == profile { return lookupValue }
        lookupKey = .some(profile)
        lookupValue = HorizonLookup(profile)
        return lookupValue
    }

    /// The skyline per whole degree for the backdrop shader ([0] when flat).
    func terrain(_ profile: HorizonProfile?) -> [Float] {
        if let terrainKey, terrainKey == profile { return terrainValue }
        terrainKey = .some(profile)
        terrainValue = profile.map { p in (0..<360).map { Float(p.altitudeDeg(atAzimuth: Double($0))) } } ?? [0]
        return terrainValue
    }

    /// Sun position, recomputed every 30 s of sky time.
    func sun(at date: Date, observer: Observer) -> HorizontalPosition {
        let bucket = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 30).rounded(.down) * 30)
        if let k = sunKey, k.0 == bucket, k.1 == observer.latitude, k.2 == observer.longitude { return sunValue }
        sunKey = (bucket, observer.latitude, observer.longitude)
        sunValue = (try? SkyPositions.position(of: .sun, at: bucket, observer: observer, refraction: .normal)) ?? sunValue
        return sunValue
    }

    func trails(_ sequence: StarTrailSequence, stars: SkyStars, observer: Observer, magnitudeLimit: Double) -> StarTrailPreview {
        let key = (sequence, observer.latitude, observer.longitude, magnitudeLimit)
        if let k = trailKey, k == key, let trailValue { return trailValue }
        let preview = StarTrailPreview(sequence: sequence, field: stars.field, observer: observer, magnitudeLimit: magnitudeLimit)
        trailKey = key
        trailValue = preview
        polarisOffset = stars.catalog.index(ofHR: 424).map {
            StarTrails.distanceFromPoleDeg(ofStarAt: $0, in: stars.field, at: sequence.start)
        }
        return preview
    }

    var polarisOffsetDeg: Double? { polarisOffset }
}

/// Builds `SkyRealismFrame` and the backdrop shader for a frame.
struct SkyRealismBuilder {
    let stars: SkyStars
    let observer: Observer
    let projector: SkyProjector
    let time: Date
    let scene: NightSkyScene
    let layers: SkyLayers
    let horizon: HorizonLookup
    let horizonProfile: HorizonProfile?
    let planetarium: Bool
    let fieldMode: Bool
    let find: SkyFindTarget?
    let trail: StarTrailSequence?
    let radiants: [SkyRadiant]
    let cache: SkyRealismCache

    var lighting: SkyLighting {
        SkyLighting(
            sun: cache.sun(at: time, observer: observer),
            moon: scene.position(of: .moon) ?? HorizontalPosition(altitudeDeg: -90, azimuthDeg: 0),
            moonPhaseAngleDeg: SkyLighting.phaseAngleDeg(illuminatedFraction: scene.moonIllumination))
    }

    func build() -> (frame: SkyRealismFrame, backdrop: SkyBackdropParams?) {
        let rotation = SkyRotation.eqjToReference(at: time, observer: observer)
        let light = lighting
        var frame = SkyRealismFrame()
        let nelm = min(max(SkyBrightness.zenithLimitingMagnitude(light), 1.5), 6.5)
        // Over the camera, only the brighter stars: the real ones are there too.
        frame.limitingMagnitude = planetarium ? nelm : min(nelm, 4.5)
        let fov = 2 * atan(projector.intrinsics.height / 2 / projector.intrinsics.fy) * 180 / .pi
        frame.starScale = min(max((100 / max(fov, 10)).squareRoot(), 0.8), 1.8)

        let catalog = stars.catalog
        if layers.stars || trail != nil {
            let projected = stars.field.project(
                through: projector, eqjToReference: rotation, magnitudeLimit: frame.limitingMagnitude,
                extinction: .typical, horizon: horizon)
            if layers.stars {
                frame.stars = projected.map {
                    SkyRealismFrame.Star(point: CGPoint(x: $0.u, y: $0.v), magnitude: $0.apparentMagnitude, color: stars.colorBucket[$0.index])
                }
            }
            let nameLimit = fov < 45 ? 3.5 : 2.2
            for p in projected where catalog.stars[p.index].vmag <= nameLimit {
                guard let name = catalog.names[catalog.stars[p.index].hr],
                      p.u > 0, p.u < projector.intrinsics.width, p.v > 0, p.v < projector.intrinsics.height else { continue }
                frame.namedStarsOnScreen.append(name)
                // With trails on, Polaris gets its own label beside the pole.
                if layers.names, !(trail != nil && catalog.stars[p.index].hr == 424) {
                    frame.labels.append(.init(text: name, point: CGPoint(x: p.u + 5, y: p.v + 4), isConstellation: false, highlighted: find == .star(hr: catalog.stars[p.index].hr)))
                }
            }
        }

        // Constellation figures and names. Figures whose centre is far
        // outside the view (the largest spans ~50°) are skipped outright.
        let width = projector.intrinsics.width, height = projector.intrinsics.height
        let boresight = projector.attitude.referenceToDevice.row3 * -1
        let halfDiagonal = atan(hypot(width / 2 / projector.intrinsics.fx, height / 2 / projector.intrinsics.fy))
        let cullCos = cos(min(halfDiagonal + 50 * .pi / 180, .pi))
        for figure in catalog.constellations {
            let highlighted = find == .constellation(figure.abbreviation)
            let centre = SkyRotation.refracted(rotation * (stars.centres[figure.abbreviation] ?? stars.field.centre(of: figure)))
            if !highlighted, (centre * boresight).sum() < cullCos { continue }
            let centreAlt = asin(max(-1, min(1, centre.z))) * 180 / .pi
            if centreAlt > -15 || highlighted, layers.constellationLines || highlighted {
                var runs: [[CGPoint]] = []
                for line in figure.lines {
                    var vectors: [SIMD3<Double>] = []
                    for hr in line {
                        guard let i = catalog.index(ofHR: hr) else { continue }
                        let r = SkyRotation.refracted(rotation * stars.field.apparentEQJ[i])
                        let alt = asin(max(-1, min(1, r.z))) * 180 / .pi
                        let az = Geodesy.normalizedAzimuth(atan2(-r.y, r.x) * 180 / .pi)
                        if alt < horizon.altitudeDeg(atAzimuth: az) - (planetarium ? 0 : 3) {
                            runs += projector.projectPath(referenceVectors: vectors).map { $0.map(Self.point) }
                            vectors = []
                        } else {
                            vectors.append(r)
                        }
                    }
                    runs += projector.projectPath(referenceVectors: vectors).map { $0.map(Self.point) }
                }
                if !runs.isEmpty { frame.figures.append((figure.abbreviation, runs, highlighted)) }
            }
            let centreAz = Geodesy.normalizedAzimuth(atan2(-centre.y, centre.x) * 180 / .pi)
            guard centreAlt > horizon.altitudeDeg(atAzimuth: centreAz), let px = projector.pixel(ofReference: centre),
                  px.u > 0, px.u < width, px.v > 0, px.v < height else { continue }
            frame.constellationsOnScreen.append(figure.name)
            if layers.names && (figure.rank <= (fov < 50 ? 3 : 2) || highlighted) {
                frame.labels.append(.init(text: figure.name.uppercased(), point: Self.point(px), isConstellation: true, highlighted: highlighted))
            }
        }

        if let trail {
            let preview = cache.trails(trail, stars: stars, observer: observer, magnitudeLimit: fov < 50 ? 5.0 : 4.5)
            let runs = preview.arcs.map { arc in
                (runs: projector.projectPath(referenceVectors: arc.points).map { $0.map(Self.point) },
                 magnitude: catalog.stars[arc.index].vmag, color: stars.colorBucket[arc.index])
            }
            let polaris = catalog.index(ofHR: 424).flatMap {
                projector.pixel(ofReference: SkyRotation.refracted(rotation * stars.field.apparentEQJ[$0]))
            }
            let pole = projector.project(preview.pole)
            frame.trails = .init(
                runs: runs, pole: pole.pixel.map(Self.point), polaris: polaris.map(Self.point),
                polarisOffsetDeg: cache.polarisOffsetDeg, framing: StarTrails.framing(of: preview.pole, projector: projector),
                sequence: trail)
        }

        for radiant in radiants {
            let r = MeteorRadiants.referenceVector(of: radiant, at: time, observer: observer)
            let pos = HorizontalPosition(reference: r)
            let hints = pos.altitudeDeg > -5
                ? MeteorRadiants.directionHints(radiant: r).flatMap { projector.projectPath(referenceVectors: $0).map { $0.map(Self.point) } }
                : []
            frame.radiants.append(.init(
                name: radiant.name, point: projector.pixel(ofReference: r).map(Self.point), position: pos, hints: hints,
                hourlyRate: MeteorRadiants.hourlyRate(radiant: radiant, radiantAltitudeDeg: pos.altitudeDeg, limitingMagnitude: nelm)))
        }

        if let find, let (name, position) = resolve(find, rotation: rotation) {
            frame.find = .init(name: name, guidance: SkyGuidance(target: position, projector: projector),
                               point: projector.project(position).pixel.map(Self.point))
        }
        return (frame, planetarium ? backdrop(rotation: rotation, lighting: light) : nil)
    }

    /// Name and apparent position of a find target.
    func resolve(_ target: SkyFindTarget, rotation: RotationMatrix) -> (String, HorizontalPosition)? {
        let catalog = stars.catalog
        switch target {
        case .constellation(let abbr):
            guard let figure = catalog.constellations.first(where: { $0.abbreviation == abbr }) else { return nil }
            return (figure.name, HorizontalPosition(reference: SkyRotation.refracted(rotation * (stars.centres[figure.abbreviation] ?? stars.field.centre(of: figure)))))
        case .star(let hr):
            guard let i = catalog.index(ofHR: hr) else { return nil }
            return (catalog.names[hr] ?? "HR \(hr)", HorizontalPosition(reference: SkyRotation.refracted(rotation * stars.field.apparentEQJ[i])))
        case .body(let object):
            guard let p = scene.position(of: object) else { return nil }
            return (object == .galacticCenter ? "Galactic Center" : object.rawValue.capitalized, p)
        case .radiant(let id):
            guard let r = radiants.first(where: { $0.id == id }) else { return nil }
            return (r.name + " radiant", HorizontalPosition(reference: MeteorRadiants.referenceVector(of: r, at: time, observer: observer)))
        }
    }

    private func backdrop(rotation: RotationMatrix, lighting l: SkyLighting) -> SkyBackdropParams {
        let k = projector.intrinsics
        // camera → device (x, −y, −z) → reference (Rᵀ).
        let camToRef = projector.attitude.referenceToDevice.transposed * RotationMatrix(rows: SIMD3(1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, 0, -1))
        let camToGal = (rotation * SkyRotation.galacticToEQJ).transposed * camToRef
        return SkyBackdropParams(
            intrinsics: SIMD4(Float(k.fx), Float(k.fy), Float(k.cx), Float(k.cy)),
            camToRef: camToRef, camToGal: camToGal,
            sun: l.sun.referenceVector, moon: l.moon.referenceVector,
            light: SIMD4(Float(l.sun.altitudeDeg), Float(l.moon.altitudeDeg), Float(l.moonPhaseAngleDeg), Float(l.darkZenithNanoLamberts)),
            options: SIMD4(Float(l.extinction.k), layers.milkyWay ? Self.milkyWayGain : 0, fieldMode ? 1 : 0, 1),
            horizon: cache.terrain(horizonProfile))
    }

    static func point(_ p: PixelPoint) -> CGPoint { CGPoint(x: p.u, y: p.v) }

    /// Milky Way surface brightness per unit of `MilkyWayModel.brightness`,
    /// in dark-sky zenith units: the Sagittarius Star Cloud (model ~1.1)
    /// comes out ~3.3× the dark sky, about 20.4 against 21.9 mag/arcsec².
    static let milkyWayGain: Float = 3.0
}
