import Foundation
import Testing
@testable import SkyCore

@Suite("Stacking")
struct StackingTests {
    // Siril, "Signal to noise ratio" tutorial: SNR grows as √N, so each doubling
    // of the stack (1, 2, 4, … 512) improves SNR by 1.41×.
    @Test func doublingTheStackGains1_41_Siril() throws {
        var frames = 1
        while frames < 512 {
            let ratio = try Stacking.snrGain(frames: 2 * frames) / Stacking.snrGain(frames: frames)
            #expect(approx(ratio, 1.41, 0.005))
            frames *= 2
        }
    }

    @Test("frames needed is ⌈gain²⌉", arguments: [
        (1.0, 1), (2.0.squareRoot(), 2), (1.5, 3), (2.0, 4), (3.0, 9), (10.0, 100),
    ])
    func framesNeeded(gain: Double, expected: Int) throws {
        #expect(try Stacking.framesNeeded(snrGain: gain) == expected)
    }

    @Test func framesNeededIsTheSmallestSufficientStack() throws {
        for gain in stride(from: 1.0, through: 20, by: 0.37) {
            let n = try Stacking.framesNeeded(snrGain: gain)
            #expect(Double(n).squareRoot() >= gain - 1e-9)
            if n > 1 { #expect(Double(n - 1).squareRoot() < gain) }
        }
    }

    @Test func planTotalsIntegrationTime() throws {
        let plan = try Stacking.plan(snrGain: 3, subExposure: 20)
        #expect(plan.frames == 9)
        #expect(plan.totalIntegration == 180)
        #expect(plan.snrGain == 3)
        let rounded = try Stacking.plan(snrGain: 2.5, subExposure: 15)
        #expect(rounded.frames == 7 && rounded.totalIntegration == 105 && rounded.snrGain >= 2.5)
    }

    @Test func rejectsBadInput() {
        #expect(throws: ExposureError.invalid(.snrGain, 0.9)) { try Stacking.framesNeeded(snrGain: 0.9) }
        #expect(throws: ExposureError.invalid(.snrGain, 1001)) { try Stacking.framesNeeded(snrGain: 1001) }
        #expect(throws: ExposureError.self) { try Stacking.framesNeeded(snrGain: .nan) }
        #expect(throws: ExposureError.invalid(.frames, 0)) { try Stacking.snrGain(frames: 0) }
        #expect(throws: ExposureError.invalid(.exposure, 0)) { try Stacking.plan(snrGain: 2, subExposure: 0) }
    }
}

@Suite("Timelapse")
struct TimelapseTests {
    // Enlaps, "Time Lapse Calculator": a 2 h (7200 s) event and a 10 s clip at 30 fps
    // need 300 frames, one every 24 s.
    @Test func intervalFromEventAndClip_Enlaps() throws {
        let plan = try Timelapse.plan(exposure: 20, fps: 30, clipSeconds: 10, eventDuration: 7200)
        #expect(plan.frames == 300)
        #expect(approx(plan.interval, 24, 1e-12))
        #expect(approx(plan.eventDuration, 7200, 1e-9))
        #expect(approx(plan.clipSeconds, 10, 1e-12))
    }

    @Test func framesAndDurationFromClip_Enlaps() throws {
        let plan = try Timelapse.plan(exposure: 20, interval: 24, fps: 30, clipSeconds: 10)
        #expect(plan.frames == 300)
        #expect(plan.eventDuration == 7200)
    }

    @Test func framesAndClipFromEvent_Enlaps() throws {
        let plan = try Timelapse.plan(exposure: 20, interval: 24, fps: 30, eventDuration: 7200)
        #expect(plan.frames == 300)
        #expect(approx(plan.clipSeconds, 10, 1e-12))
    }

    @Test func rejectsAnIntervalShorterThanExposurePlusBuffer() throws {
        #expect(throws: ExposureError.intervalTooShort(intervalSeconds: 24, minimumSeconds: 26)) {
            try Timelapse.plan(exposure: 25, fps: 30, clipSeconds: 10, eventDuration: 7200)
        }
        #expect(throws: ExposureError.intervalTooShort(intervalSeconds: 20, minimumSeconds: 21)) {
            try Timelapse.plan(exposure: 20, interval: 20, fps: 24, clipSeconds: 10)
        }
        #expect(throws: ExposureError.intervalTooShort(intervalSeconds: 22, minimumSeconds: 23)) {
            try Timelapse.plan(exposure: 20, interval: 22, fps: 24, eventDuration: 3600, buffer: 3)
        }
        // Exactly exposure + buffer is allowed; zero buffer allows back-to-back frames.
        #expect(try Timelapse.plan(exposure: 20, interval: 21, fps: 24, clipSeconds: 10).interval == 21)
        #expect(try Timelapse.plan(exposure: 20, interval: 20, fps: 24, clipSeconds: 10, buffer: 0).interval == 20)
    }

    @Test func plansRoundTrip() throws {
        for fps in [24.0, 25, 30, 60] {
            for interval in [15.0, 21, 30, 45] {
                let byClip = try Timelapse.plan(exposure: 13, interval: interval, fps: fps, clipSeconds: 12)
                let byEvent = try Timelapse.plan(exposure: 13, interval: interval, fps: fps, eventDuration: byClip.eventDuration)
                #expect(byEvent.frames == byClip.frames)
                let solved = try Timelapse.plan(exposure: 13, fps: fps, clipSeconds: 12, eventDuration: byClip.eventDuration)
                #expect(approx(solved.interval, interval, 1e-9))
            }
        }
    }

    @Test func longerIntervalMeansLongerShoot() throws {
        var previous = 0.0
        for interval in [16.0, 20, 25, 30, 60] {
            let plan = try Timelapse.plan(exposure: 15, interval: interval, fps: 24, clipSeconds: 10)
            #expect(plan.frames == 240)
            #expect(plan.eventDuration > previous)
            previous = plan.eventDuration
        }
    }

    @Test func rejectsBadInput() {
        #expect(throws: ExposureError.invalid(.fps, 0)) { try Timelapse.plan(exposure: 10, interval: 15, fps: 0, clipSeconds: 10) }
        #expect(throws: ExposureError.invalid(.clipLength, -1)) { try Timelapse.plan(exposure: 10, interval: 15, fps: 24, clipSeconds: -1) }
        #expect(throws: ExposureError.invalid(.exposure, 0)) { try Timelapse.plan(exposure: 0, interval: 15, fps: 24, clipSeconds: 10) }
        #expect(throws: ExposureError.invalid(.buffer, -1)) {
            try Timelapse.plan(exposure: 10, interval: 15, fps: 24, clipSeconds: 10, buffer: -1)
        }
        #expect(throws: ExposureError.invalid(.eventDuration, 10)) { // shorter than one interval: zero frames
            try Timelapse.plan(exposure: 10, interval: 15, fps: 24, eventDuration: 10)
        }
        #expect(throws: ExposureError.self) { try Timelapse.plan(exposure: 10, interval: .nan, fps: 24, clipSeconds: 10) }
        #expect(throws: ExposureError.self) { try Timelapse.plan(exposure: 10, fps: 24, clipSeconds: .infinity, eventDuration: 3600) }
    }
}
