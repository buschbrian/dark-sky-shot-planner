public import Foundation

/// Rotation about the image origin, then translation, in pixels:
/// p' = R(θ)·p + t. On a fixed tripod the sky turns about the celestial pole,
/// which within one frame is this rotation plus a shift (lens distortion aside).
public struct RigidTransform: Sendable, Hashable, Codable {
    public var rotation: Double
    public var tx: Double
    public var ty: Double

    public static let identity = RigidTransform(rotation: 0, tx: 0, ty: 0)

    public init(rotation: Double, tx: Double, ty: Double) {
        self.rotation = rotation
        self.tx = tx
        self.ty = ty
    }

    /// Rotation by `degrees` about `(cx, cy)`, then a shift.
    public init(rotationDegrees degrees: Double, about cx: Double, _ cy: Double, shiftX: Double = 0, shiftY: Double = 0) {
        let t = degrees * .pi / 180
        let c = cos(t), s = sin(t)
        self.init(rotation: t, tx: cx - (c * cx - s * cy) + shiftX, ty: cy - (s * cx + c * cy) + shiftY)
    }

    public func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        let c = cos(rotation), s = sin(rotation)
        return (c * x - s * y + tx, s * x + c * y + ty)
    }

    public var inverse: RigidTransform {
        let c = cos(rotation), s = sin(rotation)
        // p = Rᵀ(p' − t)
        return RigidTransform(rotation: -rotation, tx: -(c * tx + s * ty), ty: -(-s * tx + c * ty))
    }

    public var rotationDegrees: Double { rotation * 180 / .pi }

    /// This transform after `other`: p ↦ self(other(p)).
    public func composed(after other: RigidTransform) -> RigidTransform {
        let c = cos(rotation), s = sin(rotation)
        return RigidTransform(rotation: rotation + other.rotation,
                              tx: c * other.tx - s * other.ty + tx,
                              ty: s * other.tx + c * other.ty + ty)
    }
}

public struct Registration: Sendable, Hashable {
    /// Maps the frame's pixel coordinates onto the reference frame's.
    public let transform: RigidTransform
    public let matchedStars: Int
    /// RMS distance, in pixels, between matched reference stars and transformed frame stars.
    public let rmsResidual: Double

    public init(transform: RigidTransform, matchedStars: Int, rmsResidual: Double) {
        self.transform = transform
        self.matchedStars = matchedStars
        self.rmsResidual = rmsResidual
    }
}

public enum RegistrationError: Error, Sendable, Hashable {
    case tooFewStars(reference: Int, frame: Int)
    case noConsistentMatch(bestInliers: Int)
}

/// Matches two star lists without knowing the shift: every pair of bright
/// stars in the reference is compared with pairs in the frame whose
/// separation agrees (a rigid motion keeps distances), each agreement
/// proposes a rotation and shift, and the proposal most other stars agree
/// with wins. A least-squares fit over all agreeing stars refines it
/// (2-D Kabsch/Procrustes without scale).
public struct StarMatcher: Sendable {
    /// Match radius in pixels, also the pair-length tolerance.
    public var tolerance = 2.0
    /// Brightest stars per list used to propose transforms.
    public var proposalStars = 40
    /// Pairs shorter than this give poorly constrained rotations.
    public var minPairLength = 20.0
    /// Rotations beyond this are rejected (a tripod sequence turns slowly).
    public var maxRotationDegrees = 20.0
    /// Six agreeing stars: four can line up by chance between unrelated fields.
    public var minMatches = 6

    public init() {}

    public func register(reference: [DetectedStar], frame: [DetectedStar]) throws(RegistrationError) -> Registration {
        guard reference.count >= minMatches, frame.count >= minMatches else {
            throw .tooFewStars(reference: reference.count, frame: frame.count)
        }
        let ref = Array(reference.prefix(proposalStars)), cur = Array(frame.prefix(proposalStars))
        let pairs = Self.pairs(cur, minLength: minPairLength)
        let maxRotation = maxRotationDegrees * .pi / 180
        var best: (transform: RigidTransform, inliers: Int)?
        let enough = Int(0.8 * Double(min(ref.count, cur.count)))
        search: for a in 0..<ref.count {
            for b in (a + 1)..<ref.count {
                let rx = ref[b].x - ref[a].x, ry = ref[b].y - ref[a].y
                let length = (rx * rx + ry * ry).squareRoot()
                guard length >= minPairLength else { continue }
                var k = Self.lowerBound(pairs, length - tolerance)
                while k < pairs.count, pairs[k].length <= length + tolerance {
                    let p = pairs[k]
                    k += 1
                    for (i, j) in [(p.i, p.j), (p.j, p.i)] {
                        let fx = cur[j].x - cur[i].x, fy = cur[j].y - cur[i].y
                        var theta = atan2(ry, rx) - atan2(fy, fx)
                        theta = atan2(sin(theta), cos(theta))
                        guard abs(theta) <= maxRotation else { continue }
                        let c = cos(theta), s = sin(theta)
                        let t = RigidTransform(rotation: theta,
                                               tx: ref[a].x - (c * cur[i].x - s * cur[i].y),
                                               ty: ref[a].y - (s * cur[i].x + c * cur[i].y))
                        let inliers = Self.matches(t, frame: cur, reference: ref, radius: tolerance).count
                        if inliers > (best?.inliers ?? 0) { best = (t, inliers) }
                        if inliers >= enough { break search }
                    }
                }
            }
        }
        guard let best, best.inliers >= minMatches else {
            throw .noConsistentMatch(bestInliers: best?.inliers ?? 0)
        }
        // Refine over the full lists, tightening the radius as the fit improves.
        var transform = best.transform
        var matched: [(Int, Int)] = []
        for radius in [tolerance, tolerance * 0.75, tolerance * 0.5] {
            let m = Self.matches(transform, frame: frame, reference: reference, radius: radius)
            guard m.count >= minMatches else { break }
            matched = m
            transform = Self.fit(matched.map { (frame[$0.0], reference[$0.1]) })
        }
        guard matched.count >= minMatches else { throw .noConsistentMatch(bestInliers: matched.count) }
        var sq = 0.0
        for (f, r) in matched {
            let p = transform.apply(frame[f].x, frame[f].y)
            sq += (p.x - reference[r].x) * (p.x - reference[r].x) + (p.y - reference[r].y) * (p.y - reference[r].y)
        }
        return Registration(transform: transform, matchedStars: matched.count,
                            rmsResidual: (sq / Double(matched.count)).squareRoot())
    }

    /// Weighted least-squares rotation and shift taking `frame` points onto
    /// `reference` points. Each pair weighs by the fainter star's flux, since
    /// a bright star's centroid is far better measured than a faint one's.
    public static func fit(_ pairs: [(frame: DetectedStar, reference: DetectedStar)]) -> RigidTransform {
        var sw = 0.0, fcx = 0.0, fcy = 0.0, rcx = 0.0, rcy = 0.0
        for (f, r) in pairs {
            let wgt = max(min(f.flux, r.flux), 1e-12)
            sw += wgt
            fcx += wgt * f.x; fcy += wgt * f.y
            rcx += wgt * r.x; rcy += wgt * r.y
        }
        fcx /= sw; fcy /= sw; rcx /= sw; rcy /= sw
        var sxx = 0.0, sxy = 0.0
        for (f, r) in pairs {
            let wgt = max(min(f.flux, r.flux), 1e-12)
            let fx = f.x - fcx, fy = f.y - fcy, rx = r.x - rcx, ry = r.y - rcy
            sxx += wgt * (fx * rx + fy * ry)
            sxy += wgt * (fx * ry - fy * rx)
        }
        let theta = atan2(sxy, sxx)
        let c = cos(theta), s = sin(theta)
        return RigidTransform(rotation: theta, tx: rcx - (c * fcx - s * fcy), ty: rcy - (s * fcx + c * fcy))
    }

    /// One-to-one nearest matches within `radius` (each reference star used once).
    static func matches(_ t: RigidTransform, frame: [DetectedStar], reference: [DetectedStar], radius: Double) -> [(Int, Int)] {
        let r2 = radius * radius
        var used = Set<Int>()
        var out: [(Int, Int)] = []
        for (i, star) in frame.enumerated() {
            let p = t.apply(star.x, star.y)
            var bestIndex = -1, bestD = r2
            for (j, ref) in reference.enumerated() where !used.contains(j) {
                let dx = ref.x - p.x, dy = ref.y - p.y
                let d = dx * dx + dy * dy
                if d <= bestD { bestD = d; bestIndex = j }
            }
            if bestIndex >= 0 {
                used.insert(bestIndex)
                out.append((i, bestIndex))
            }
        }
        return out
    }

    struct Pair { let i: Int; let j: Int; let length: Double }

    static func pairs(_ stars: [DetectedStar], minLength: Double) -> [Pair] {
        var out: [Pair] = []
        for i in stars.indices {
            for j in (i + 1)..<stars.count {
                let dx = stars[j].x - stars[i].x, dy = stars[j].y - stars[i].y
                let d = (dx * dx + dy * dy).squareRoot()
                if d >= minLength { out.append(Pair(i: i, j: j, length: d)) }
            }
        }
        return out.sorted { $0.length < $1.length }
    }

    static func lowerBound(_ pairs: [Pair], _ length: Double) -> Int {
        var lo = 0, hi = pairs.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if pairs[mid].length < length { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
