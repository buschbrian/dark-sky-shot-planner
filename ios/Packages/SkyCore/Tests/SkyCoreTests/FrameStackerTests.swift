import Foundation
import Testing
@testable import SkyCore

@Suite("Sigma clipping")
struct SigmaClipTests {
    @Test func rejectsASingleOutlier() {
        #expect(SigmaClip.standard.combine([10, 11, 9, 10, 10, 11, 9, 10, 400]) == 10)
    }

    @Test func isThePlainMeanWithoutOutliers() {
        let values: [Float] = [8, 9, 10, 11, 12]
        #expect(SigmaClip.standard.combine(values) == 10)
    }

    @Test func fewerThanThreeValuesAreAveraged() {
        #expect(SigmaClip.standard.combine([4, 100]) == 52)
        #expect(SigmaClip.standard.combine([7]) == 7)
        #expect(SigmaClip.standard.combine([]).isNaN)
    }

    @Test func ignoresNaNFromUncoveredFrames() {
        #expect(SigmaClip.standard.combine([.nan, 10, 10, .nan, 10]) == 10)
    }

    @Test func rejectsLowOutliersToo() {
        // A frame darkened by a passing cloud.
        #expect(SigmaClip.standard.combine([100, 101, 99, 100, 100, 101, 99, 100, 5]) == 100)
    }
}

@Suite("Frame stacking")
struct FrameStackerTests {
    static let w = 320, h = 240, frames = 8

    static let stars = SyntheticStarField.stars(count: 70, width: w, height: h, seed: 5)

    /// Frame i is the reference turned by i × 0.05° about a pole above the frame and drifted.
    static func truth(_ i: Int) -> RigidTransform {
        RigidTransform(rotationDegrees: 0.05 * Double(i), about: 160, -1_500, shiftX: 0.37 * Double(i), shiftY: -0.21 * Double(i))
    }

    static let streak = SyntheticStarField.Streak(x0: 10, y0: 200, x1: 310, y1: 40, brightness: 5_000)

    static func frame(_ i: Int, streak: Bool = true) -> RasterU16 {
        SyntheticStarField.render(stars, width: w, height: h, frameFromReference: truth(i),
                                  streak: streak && i == 3 ? Self.streak : nil, seed: 100 + UInt64(i))
    }

    static let clean = SyntheticStarField.render(stars, width: w, height: h, noiseSigma: 0, seed: 0)

    /// RMS difference from the noiseless reference over sky pixels (no star
    /// light within reach; resampling softens star cores, which is not noise)
    /// at least 20 px from the edge.
    static func rmsError(_ r: RasterU16) -> Double {
        let a = r.values, b = clean.values
        var sq = 0.0, n = 0.0
        for y in 20..<(h - 20) {
            for x in 20..<(w - 20) {
                guard (-2...2).allSatisfy({ dy in (-2...2).allSatisfy { dx in
                    b[(y + dy) * w + x + dx] <= 2_001 } }) else { continue }
                let d = Double(a[y * w + x]) - Double(b[y * w + x])
                sq += d * d
                n += 1
            }
        }
        return (sq / n).squareRoot()
    }

    /// Mean excess over the background along the streak's path, in the reference frame.
    static func streakExcess(_ r: RasterU16) -> Double {
        let v = r.values, c = clean.values
        var total = 0.0, n = 0.0
        for s in stride(from: 0.1, through: 0.9, by: 0.01) {
            // Streak drawn in frame 3's coordinates; map it back to the reference.
            let fx = streak.x0 + s * (streak.x1 - streak.x0), fy = streak.y0 + s * (streak.y1 - streak.y0)
            let p = truth(3).inverse.apply(fx, fy)
            let i = Int(p.y.rounded()) * w + Int(p.x.rounded())
            total += Double(v[i]) - Double(c[i])
            n += 1
        }
        return total / n
    }

    @Test func sigmaClippedStackCutsNoiseAndDropsTheSatellite() {
        let frames = (0..<Self.frames).map { Self.frame($0) }
        let transforms = (0..<Self.frames).map { Self.truth($0).inverse }
        let result = FrameStacker().sigmaClipped(frames, transforms: transforms)
        let single = Self.rmsError(frames[0])
        let stacked = Self.rmsError(result.raster)
        // √8 = 2.8× lower noise from averaging alone; clipping costs a little.
        #expect(stacked < single / 2.3)
        #expect(Self.streakExcess(result.raster) < 60)
    }

    @Test func plainMeanKeepsAFaintSatellite() {
        var mean = StackAccumulator(mode: .mean, width: Self.w, height: Self.h, channels: 1)
        for i in 0..<Self.frames { mean.add(Self.frame(i), transform: Self.truth(i).inverse) }
        // 5000 / 8 frames, less interpolation losses: why the mean alone is not enough.
        #expect(Self.streakExcess(mean.result) > 400)
    }

    @Test func maximumKeepsTheTrail() {
        var max = StackAccumulator(mode: .maximum, width: Self.w, height: Self.h, channels: 1)
        for i in 0..<Self.frames { max.add(Self.frame(i)) }
        #expect(max.frames == Self.frames)
        // Unaligned: the streak survives at full strength (star-trail behaviour).
        #expect(Self.minAlongStreak(max.result.values) >= 6_500)
    }

    static func minAlongStreak(_ v: [UInt16]) -> UInt16 {
        var best = UInt16.max
        for s in stride(from: 0.1, through: 0.9, by: 0.01) {
            let x = Int((streak.x0 + s * (streak.x1 - streak.x0)).rounded())
            let y = Int((streak.y0 + s * (streak.y1 - streak.y0)).rounded())
            best = min(best, v[y * w + x])
        }
        return best
    }

    @Test func endToEndRegistrationThenStack() throws {
        let frames = (0..<Self.frames).map { Self.frame($0) }
        let detector = StarDetector()
        let reference = detector.detect(ImagePlane.luminance(frames[0]))
        var transforms: [RigidTransform] = []
        for f in frames {
            let reg = try StarMatcher().register(reference: reference, frame: detector.detect(ImagePlane.luminance(f)))
            transforms.append(reg.transform)
        }
        for (i, t) in transforms.enumerated() {
            let p = t.apply(Self.truth(i).apply(300, 220).x, Self.truth(i).apply(300, 220).y)
            #expect(hypot(p.x - 300, p.y - 220) < 0.1)
        }
        let stacked = FrameStacker().sigmaClipped(frames, transforms: transforms).raster
        #expect(Self.rmsError(stacked) < Self.rmsError(frames[0]) / 2.3)
    }

    @Test func smallBandsGiveTheSameStack() {
        let frames = (0..<4).map { Self.frame($0, streak: false) }
        let transforms = (0..<4).map { Self.truth($0).inverse }
        let big = FrameStacker().sigmaClipped(frames, transforms: transforms).raster.values
        let tiny = FrameStacker(bandBudgetBytes: 1).sigmaClipped(frames, transforms: transforms).raster.values
        #expect(big == tiny)
    }

    @Test func identityStackOfIdenticalFramesIsThatFrame() {
        let f = Self.frame(0, streak: false)
        let r = FrameStacker().sigmaClipped([f, f, f], transforms: [.identity, .identity, .identity])
        #expect(r.raster.values == f.values)
        #expect(r.uncovered == 0)
    }

    @Test func rgbChannelsStayApart() {
        let values: [UInt16] = (0..<(4 * 3 * 3)).map { UInt16($0 % 3 == 0 ? 1_000 : $0 % 3 == 1 ? 2_000 : 3_000) }
        let f = RasterU16(width: 4, height: 3, channels: 3, values: values)
        let r = FrameStacker().sigmaClipped([f, f, f, f], transforms: Array(repeating: .identity, count: 4))
        #expect(r.raster.values == values)
    }

    @Test func pixelsNoFrameCoversAreCountedAndZero() {
        let f = Self.frame(0, streak: false)
        let shifted = RigidTransform(rotation: 0, tx: 50, ty: 0)
        let r = FrameStacker().sigmaClipped([f], transforms: [shifted])
        #expect(r.uncovered == 50 * Self.h)
        #expect(r.raster.values[10] == 0)
    }
}
