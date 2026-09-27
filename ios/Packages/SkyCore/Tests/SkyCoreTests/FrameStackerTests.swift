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

    @Test func sigmaClippedStackCutsNoiseAndDropsTheSatellite() throws {
        let frames = (0..<Self.frames).map { Self.frame($0) }
        let transforms = (0..<Self.frames).map { Self.truth($0).inverse }
        let result = try FrameStacker().sigmaClipped(frames, transforms: transforms)
        let single = Self.rmsError(frames[0])
        let stacked = Self.rmsError(result.raster)
        // √8 = 2.8× lower noise from averaging alone; clipping costs a little.
        #expect(stacked < single / 2.3)
        // The satellite was 5000 above the sky; what is left of it is under 1 %.
        #expect(Self.streakExcess(result.raster) < 0.01 * Self.streak.brightness)
    }

    @Test func plainMeanKeepsAFaintSatellite() throws {
        var mean = StackAccumulator(mode: .mean, width: Self.w, height: Self.h, channels: 1)
        for i in 0..<Self.frames { try mean.add(Self.frame(i), transform: Self.truth(i).inverse) }
        // 5000 / 8 frames, less interpolation losses: why the mean alone is not enough.
        #expect(Self.streakExcess(mean.result) > 400)
    }

    @Test func maximumKeepsTheTrail() throws {
        var max = StackAccumulator(mode: .maximum, width: Self.w, height: Self.h, channels: 1)
        for i in 0..<Self.frames { try max.add(Self.frame(i)) }
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

    /// Star trails: a star 400 px from the pole turns 0.1° per 1 s frame, so it
    /// moves 0.7 px while the shutter is open and the frames follow one another
    /// without a gap. The maximum of the frames draws one unbroken arc.
    @Test func maximumDrawsContinuousArcs() throws {
        let w = 320, h = 240, frames = 40
        let pole = (x: 160.0, y: -200.0), radius = 400.0, start = 80.0 * .pi / 180, step = 0.1 * .pi / 180
        func position(_ angle: Double) -> (x: Double, y: Double) {
            (pole.x + radius * cos(angle), pole.y + radius * sin(angle))
        }
        var acc = StackAccumulator(mode: .maximum, width: w, height: h, channels: 1)
        for i in 0..<frames {
            // One exposure: the star smeared over its path, as 8 sub-positions.
            let sub = (0..<8).map { k -> SyntheticStarField.Star in
                let p = position(start + step * (Double(i) + Double(k) / 8))
                return .init(x: p.x, y: p.y, flux: 40_000 / 8)
            }
            try acc.add(SyntheticStarField.render(sub, width: w, height: h, seed: UInt64(i + 1)))
        }
        let v = acc.result.values
        // Sample the true arc every 0.25 px: every sample is well above the sky.
        var lowest = UInt16.max
        var angle = start + step * 0.5
        while angle < start + step * (Double(frames) - 0.5) {
            let p = position(angle)
            lowest = min(lowest, v[Int(p.y.rounded()) * w + Int(p.x.rounded())])
            angle += 0.25 / radius
        }
        // Sky 2000 ± 40 (the maximum of 40 frames sits near 2000 + 2.3σ); a gap would read ~2100.
        #expect(lowest > 2_600)
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
        let stacked = try FrameStacker().sigmaClipped(frames, transforms: transforms).raster
        #expect(Self.rmsError(stacked) < Self.rmsError(frames[0]) / 2.3)
    }

    @Test func smallBandsGiveTheSameStack() throws {
        let frames = (0..<4).map { Self.frame($0, streak: false) }
        let transforms = (0..<4).map { Self.truth($0).inverse }
        let big = try FrameStacker().sigmaClipped(frames, transforms: transforms).raster.values
        let tiny = try FrameStacker(bandBudgetBytes: 1).sigmaClipped(frames, transforms: transforms).raster.values
        #expect(big == tiny)
    }

    @Test func identityStackOfIdenticalFramesIsThatFrame() throws {
        let f = Self.frame(0, streak: false)
        let r = try FrameStacker().sigmaClipped([f, f, f], transforms: [.identity, .identity, .identity])
        #expect(r.raster.values == f.values)
        #expect(r.uncovered == 0)
    }

    @Test func rgbChannelsStayApart() throws {
        let values: [UInt16] = (0..<(4 * 3 * 3)).map { UInt16($0 % 3 == 0 ? 1_000 : $0 % 3 == 1 ? 2_000 : 3_000) }
        let f = RasterU16(width: 4, height: 3, channels: 3, values: values)
        let r = try FrameStacker().sigmaClipped([f, f, f, f], transforms: Array(repeating: .identity, count: 4))
        #expect(r.raster.values == values)
    }

    @Test func pixelsNoFrameCoversAreCountedAndZero() throws {
        let f = Self.frame(0, streak: false)
        let shifted = RigidTransform(rotation: 0, tx: 50, ty: 0)
        let r = try FrameStacker().sigmaClipped([f], transforms: [shifted])
        #expect(r.uncovered == 50 * Self.h)
        #expect(r.raster.values[10] == 0)
    }

    /// Stop means stop: a 20-frame 12 MP stack, cancelled half a second in,
    /// returns within a second of the cancel.
    @Test func cancellingABigStackReturnsWithinASecond() async throws {
        let w = 4032, h = 3024
        let frame = RasterU16(width: w, height: h, channels: 3, values: [UInt16](repeating: 2_000, count: w * h * 3))
        let frames = Array(repeating: frame, count: 20)
        let transforms = (0..<20).map { RigidTransform(rotationDegrees: 0.01 * Double($0), about: 2_000, -8_000) }
        let task = Task.detached { try FrameStacker().sigmaClipped(frames, transforms: transforms) }
        try await Task.sleep(for: .milliseconds(500))
        let cancelled = ContinuousClock.now
        task.cancel()
        let outcome = await task.result
        let waited = ContinuousClock.now - cancelled
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(waited < .seconds(1))
    }

    @Test func cancellingTheTrailStackReturnsWithinASecond() async throws {
        let w = 4032, h = 3024
        let frame = RasterU16(width: w, height: h, channels: 3, values: [UInt16](repeating: 2_000, count: w * h * 3))
        let ready = AsyncStream<Void>.makeStream()
        let task = Task.detached {
            // Allocating the 12 MP accumulator is setup, not stacking: time from after it.
            var acc = StackAccumulator(mode: .maximum, width: w, height: h, channels: 3)
            ready.continuation.finish()
            for _ in 0..<100 { try acc.add(frame) }
            return acc.frames
        }
        for await _ in ready.stream {}
        try await Task.sleep(for: .milliseconds(500))
        let cancelled = ContinuousClock.now
        task.cancel()
        let outcome = await task.result
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(ContinuousClock.now - cancelled < .seconds(1))
    }
}
