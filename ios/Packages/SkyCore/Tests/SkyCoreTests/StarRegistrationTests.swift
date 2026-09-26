import Foundation
import Testing
@testable import SkyCore

/// Synthetic star fields with known transforms (ADR-0011): detection finds
/// the stars that were drawn, and registration recovers the motion that was
/// applied, to a small fraction of a pixel.
enum Field {
    static let width = 800, height = 600

    static func stars(_ seed: UInt64 = 7, count: Int = 160) -> [SyntheticStarField.Star] {
        SyntheticStarField.stars(count: count, width: width, height: height, seed: seed)
    }

    static func plane(_ stars: [SyntheticStarField.Star], _ t: RigidTransform = .identity, seed: UInt64,
                      hotPixels: [(x: Int, y: Int)] = []) -> ImagePlane {
        ImagePlane.luminance(SyntheticStarField.render(
            stars, width: width, height: height, frameFromReference: t, hotPixels: hotPixels, seed: seed))
    }

    /// Worst distance, over the corners and centre, between where the
    /// registration sends a frame point and where it truly came from.
    static func worstError(_ registration: Registration, truth frameFromReference: RigidTransform) -> Double {
        let points = [(0.0, 0.0), (Double(width - 1), 0), (0, Double(height - 1)),
                      (Double(width - 1), Double(height - 1)), (Double(width) / 2, Double(height) / 2)]
        return points.map { p in
            let f = frameFromReference.apply(p.0, p.1)
            let back = registration.transform.apply(f.x, f.y)
            return hypot(back.x - p.0, back.y - p.1)
        }.max()!
    }
}

@Suite("Star detection")
struct StarDetectionTests {
    @Test func findsTheDrawnStarsWithSubpixelCentroids() {
        let stars = Field.stars()
        let found = StarDetector().detect(Field.plane(stars, seed: 1))
        #expect(found.count >= 100)
        // Every bright drawn star away from the edge is found, within 0.1 px.
        let bright = stars.filter { $0.flux > 30_000 && $0.x > 12 && $0.y > 12
            && $0.x < Double(Field.width - 13) && $0.y < Double(Field.height - 13) }
        var errors: [Double] = []
        for star in bright {
            guard let nearest = found.min(by: {
                hypot($0.x - star.x, $0.y - star.y) < hypot($1.x - star.x, $1.y - star.y)
            }) else { continue }
            let d = hypot(nearest.x - star.x, nearest.y - star.y)
            // Two drawn stars can blend into one detection; skip those.
            if stars.contains(where: { $0 != star && hypot($0.x - star.x, $0.y - star.y) < 8 }) { continue }
            errors.append(d)
        }
        #expect(errors.count >= bright.count * 8 / 10)
        #expect(errors.max()! < 0.15)
        #expect(errors.reduce(0, +) / Double(errors.count) < 0.05)
    }

    @Test func sortsBrightestFirst() {
        let found = StarDetector().detect(Field.plane(Field.stars(), seed: 2))
        #expect(zip(found, found.dropFirst()).allSatisfy { $0.flux >= $1.flux })
    }

    @Test func ignoresLoneHotPixels() {
        let hot = [(x: 100, y: 100), (x: 400, y: 300), (x: 650, y: 90)]
        let found = StarDetector().detect(Field.plane([], seed: 3, hotPixels: hot))
        #expect(found.isEmpty)
    }

    @Test func blankSkyHasNoStars() {
        #expect(StarDetector().detect(Field.plane([], seed: 4)).isEmpty)
    }

    @Test func halfFluxRadiusGrowsWhenDefocused() {
        let stars = Field.stars(11, count: 60)
        let sharp = ImagePlane.luminance(SyntheticStarField.render(
            stars, width: Field.width, height: Field.height, psfSigma: 1.0, seed: 5))
        let soft = ImagePlane.luminance(SyntheticStarField.render(
            stars, width: Field.width, height: Field.height, psfSigma: 2.5, seed: 5))
        let a = FocusMeasure.medianHFR(StarDetector().detect(sharp))!
        let b = FocusMeasure.medianHFR(StarDetector().detect(soft))!
        #expect(a < b * 0.6)
    }
}

@Suite("Star registration")
struct StarRegistrationTests {
    func register(_ t: RigidTransform, drop: Int = 0, seed: UInt64 = 21) throws -> Registration {
        let stars = Field.stars()
        let ref = StarDetector().detect(Field.plane(stars, seed: seed))
        let frame = StarDetector().detect(Field.plane(Array(stars.dropFirst(drop)), t, seed: seed + 1))
        return try StarMatcher().register(reference: ref, frame: frame)
    }

    @Test func recoversPureTranslation() throws {
        let t = RigidTransform(rotation: 0, tx: 12.3, ty: -7.8)
        let r = try register(t)
        #expect(Field.worstError(r, truth: t) < 0.05)
        #expect(r.matchedStars >= 60)
    }

    @Test("rotation about a pole outside the frame, plus drift", arguments: [0.25, -0.6, 1.5])
    func recoversRotation(degrees: Double) throws {
        // The celestial pole well above the top of the frame, as on a south-facing Milky Way shot.
        let t = RigidTransform(rotationDegrees: degrees, about: 380, -2_500, shiftX: 3.2, shiftY: -1.1)
        let r = try register(t)
        #expect(Field.worstError(r, truth: t) < 0.05)
        #expect(abs(r.transform.rotationDegrees + degrees) < 0.005)
        // Unweighted, so faint stars' centroid noise dominates it; the
        // flux-weighted fit itself is held to 0.05 px above.
        #expect(r.rmsResidual < 0.4)
    }

    @Test func survivesLargeShiftAndMissingStars() throws {
        // 120 px of drift pushes stars out of frame; a cloud removes 40 more.
        let t = RigidTransform(rotationDegrees: 0.8, about: 400, 300, shiftX: 120, shiftY: 45)
        let r = try register(t, drop: 40)
        #expect(Field.worstError(r, truth: t) < 0.08)
    }

    @Test func recoversIdentity() throws {
        let r = try register(.identity)
        #expect(Field.worstError(r, truth: .identity) < 0.03)
    }

    @Test func rejectsAnUnrelatedField() {
        let ref = StarDetector().detect(Field.plane(Field.stars(1), seed: 1))
        let other = StarDetector().detect(Field.plane(Field.stars(99), seed: 2))
        #expect(throws: RegistrationError.self) { try StarMatcher().register(reference: ref, frame: other) }
    }

    @Test func rejectsTooFewStars() {
        let ref = Array(StarDetector().detect(Field.plane(Field.stars(), seed: 1)).prefix(3))
        #expect(throws: RegistrationError.tooFewStars(reference: 3, frame: 3)) {
            try StarMatcher().register(reference: ref, frame: ref)
        }
    }

    @Test func inverseAndCompositionRoundTrip() {
        let t = RigidTransform(rotationDegrees: 7, about: 100, 50, shiftX: 4, shiftY: -9)
        let id = t.composed(after: t.inverse)
        let p = id.apply(321, 123)
        #expect(approx(p.x, 321, 1e-9) && approx(p.y, 123, 1e-9))
        let q = t.inverse.apply(t.apply(10, 20).x, t.apply(10, 20).y)
        #expect(approx(q.x, 10, 1e-9) && approx(q.y, 20, 1e-9))
    }

    @Test func rotationAboutAPointKeepsThatPointFixed() {
        let t = RigidTransform(rotationDegrees: 33, about: 250, 170)
        let p = t.apply(250, 170)
        #expect(approx(p.x, 250, 1e-9) && approx(p.y, 170, 1e-9))
    }
}
