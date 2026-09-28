import Foundation
import Testing
@testable import SkyCore

@Suite("Capture guidance")
struct CaptureGuidanceTests {
    @Test func durations() {
        #expect(CaptureWording.duration(1) == "1 s")
        #expect(CaptureWording.duration(0.5) == "0.5 s")
        #expect(CaptureWording.duration(0.25) == "0.25 s")
        #expect(CaptureWording.duration(8.64) == "8.64 s")
        #expect(CaptureWording.duration(12.4) == "12 s")
        #expect(CaptureWording.duration(60) == "1 min")
        #expect(CaptureWording.duration(125) == "2 min 5 s")
        #expect(CaptureWording.duration(3600) == "1 h")
        #expect(CaptureWording.duration(3780) == "1 h 3 min")
    }

    /// Review §7: "longest this camera allows" only at the maximum.
    @Test func exposureLabelOnlyClaimsTheLongestAtTheMaximum() {
        #expect(CaptureWording.exposurePerFrame(chosen: 1, maximum: 1) == "1 s, the longest this camera allows")
        #expect(CaptureWording.exposurePerFrame(chosen: 0.97, maximum: 1) == "1 s, the longest this camera allows")
        let lowered = CaptureWording.exposurePerFrame(chosen: 0.5, maximum: 1)
        #expect(lowered == "0.5 s; maximum 1 s")
        #expect(!lowered.contains("longest"))
        #expect(CaptureWording.exposurePerFrame(chosen: 0.9, maximum: 1) == "0.9 s; maximum 1 s")
    }

    @Test func ceilingIsThisPhoneNotEveryIPhone() {
        let text = CaptureWording.ceiling(1, device: "this iPhone", system: "iOS 27.2")
        #expect(text.hasPrefix("1 s per frame: what this iPhone reports"))
        #expect(text.contains("iOS 27.2"))
        #expect(text.contains("may allow a different length"))
    }

    @Test func starTrailLimitNeverReadsAsAnExposure() {
        let long = CaptureWording.starTrailLimit(npf: 8.6, cameraMaximum: 1)
        #expect(long.contains("8.6 s"))
        #expect(long.contains("not a length this camera can expose"))
        let short = CaptureWording.starTrailLimit(npf: 0.8, cameraMaximum: 1)
        #expect(short.contains("keep each frame at or under 0.8 s"))
    }

    @Test func fourDurationsStayApart() throws {
        // 9 × 1 s frames, no gaps, 5 s self-timer; NPF 8.6 s.
        let plan = try CapturePlan(frames: 9, subExposure: 1, gap: 0, bytesPerFrame: 1, workingBytesPerFrame: 0, stackBytes: 0)
        let d = CaptureDurations(plan: plan, cameraMaximum: 1, selfTimer: 5, npf: 8.6)
        #expect(d.perFrame == 1)
        #expect(d.integration == 9)
        #expect(d.sequence == 14)
        #expect(d.starTrailLimit == 8.6)
        // Trails with gaps: 20 frames every 3 s of 1 s exposures.
        let trails = try CapturePlan(frames: 20, subExposure: 1, gap: 2, bytesPerFrame: 1, workingBytesPerFrame: 0, stackBytes: 0)
        let t = CaptureDurations(plan: trails, cameraMaximum: 1, selfTimer: 0, npf: nil)
        #expect(t.integration == 20)
        #expect(t.sequence == 60)
    }

    @Test func resolutionChoicesAndStorage() {
        // The iPhone 18 Pro Max's best astro format (CAPTURE-LIMITS.md).
        let sizes = [CaptureResolution(width: 4032, height: 3024), CaptureResolution(width: 5712, height: 4284),
                     CaptureResolution(width: 8064, height: 6048), CaptureResolution(width: 4032, height: 3024)]
        let choices = CaptureResolution.choices(from: sizes)
        #expect(choices.map(\.title) == ["12 MP", "48 MP"])
        #expect(choices[0].estimatedFrameBytes(raw: true) == 24_873_246)
        #expect(choices[1].estimatedFrameBytes(raw: true) == 99_492_986)
        #expect(choices[0].estimatedFrameBytes(raw: false) == 4_267_468)
        #expect(CaptureResolution.choices(from: [CaptureResolution(width: 4032, height: 3024)]).count == 1)
        #expect(CaptureResolution.choices(from: []).isEmpty)
    }

    @Test func trailDesignKeepsTheSpanAndShootsBackToBack() throws {
        // The Sky designer's default: 60 min of 29 s frames every 30 s.
        let design = try StarTrailSequence(start: Date(timeIntervalSince1970: 0), duration: 3600, exposure: 29, interval: 30)
        let plan = PhoneTrailPlan(design: design, maxExposure: 1)
        #expect(plan.minutes == 60)
        #expect(plan.interval == 1)
        #expect(!plan.clamped)
        let long = try StarTrailSequence(start: Date(timeIntervalSince1970: 0), duration: 4 * 3600, exposure: 29, interval: 30)
        let clamped = PhoneTrailPlan(design: long, maxExposure: 1)
        #expect(clamped.minutes == 120)
        #expect(clamped.clamped)
        #expect(clamped.designMinutes.rounded() == 240)
    }

    @Test func recommendedPreset() {
        let p = CapturePreset(maxExposure: 1, isoRange: 55...12_320, apertures: [1.48, 1.8, 2.8, 4], rawAvailable: true)
        #expect(p.exposure == 1)
        #expect(p.iso == 3200)
        #expect(p.aperture == 1.48)
        #expect(p.selfTimer == 5)
        #expect(p.raw)
        #expect((try? Stacking.framesNeeded(snrGain: p.snrGain)) == 9)
        // The ultra wide stops at ISO 3,600; a lower ceiling clamps.
        #expect(CapturePreset(maxExposure: 1, isoRange: 15...2000, apertures: [2.2], rawAvailable: false).iso == 2000)
    }

    @Test func outcomeCounts() {
        let aligned = CaptureOutcome(kind: .stack, planned: 40, saved: 38, used: 35, unalignedReason: nil, integration: 35)
        #expect(aligned.rejected == 3)
        #expect(aligned.aligned == 35)
        #expect(!aligned.isUnaligned)
        let fallback = CaptureOutcome(kind: .stack, planned: 5, saved: 5, used: 5,
                                      unalignedReason: "Only 2 of 5 frames aligned on stars", integration: 5)
        #expect(fallback.isUnaligned)
        #expect(fallback.aligned == nil)
        let trails = CaptureOutcome(kind: .trails, planned: 100, saved: 100, used: 100, unalignedReason: nil, integration: 100)
        #expect(trails.aligned == nil)
        #expect(!trails.isUnaligned)
    }
}
