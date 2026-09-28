public import Foundation

/// The capture screen's wording for times, kept in one tested place so the
/// four durations of a phone sequence never read as one another (product
/// review 2026-09-27 §7): the exposure of each frame, the shutter-open total,
/// the wall-clock length of the sequence, and the star-trailing (NPF) limit,
/// which is a property of the stars and lens, not a setting the camera has.
public enum CaptureWording {
    /// "1 s", "0.5 s", "0.25 s", "2 min 5 s", "1 h 3 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 {
            if s >= 10 || s.rounded() == s { return "\(Int(s.rounded())) s" }
            var text = String(format: "%.2f", s)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            return text + " s"
        }
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        return sec > 0 ? "\(m) min \(sec) s" : "\(m) min"
    }

    /// The exposure row. At the ceiling it says so; below it, it states the
    /// chosen value and the ceiling, never "the longest" for a lowered slider.
    public static func exposurePerFrame(chosen: TimeInterval, maximum: TimeInterval) -> String {
        if isAtMaximum(chosen, maximum) {
            return "\(duration(maximum)), the longest this camera allows"
        }
        return "\(duration(chosen)); maximum \(duration(maximum))"
    }

    /// Within half a slider step (0.1 s) of the ceiling counts as at it.
    public static func isAtMaximum(_ chosen: TimeInterval, _ maximum: TimeInterval) -> Bool {
        chosen >= maximum - 0.05
    }

    /// The ceiling as evidence from this phone, not a fact about iPhones.
    public static func ceiling(_ maximum: TimeInterval, device: String, system: String) -> String {
        "\(duration(maximum)) per frame: what \(device) reports for this camera on \(system). Other iPhones or iOS versions may allow a different length."
    }

    /// The star-trailing limit, worded so it cannot read as an available exposure.
    public static func starTrailLimit(npf: TimeInterval, cameraMaximum: TimeInterval) -> String {
        if npf > cameraMaximum {
            return "Stars stay points for about \(duration(npf)) with this lens (NPF). That is a limit set by the stars, not a length this camera can expose: frames stop at \(duration(cameraMaximum)), so longer light comes from stacking."
        }
        return "Stars start to trail after about \(duration(npf)) with this lens (NPF), shorter than this camera's \(duration(cameraMaximum)) maximum: keep each frame at or under \(duration(npf))."
    }
}

/// The four numbers of one planned sequence, kept apart.
public struct CaptureDurations: Sendable, Hashable {
    /// Shutter open for each frame; never more than `cameraMaximum`.
    public let perFrame: TimeInterval
    /// What this phone's camera format reports as its longest exposure.
    public let cameraMaximum: TimeInterval
    public let frames: Int
    /// Frames × exposure: the light the stack collects.
    public let integration: TimeInterval
    /// Wall clock from Start to the last frame: self-timer, the frames and
    /// the gaps between them. Settling and thermal pauses can add to it.
    public let sequence: TimeInterval
    /// NPF for this lens, a limit set by the stars (nil until known).
    public let starTrailLimit: TimeInterval?

    public init(plan: CapturePlan, cameraMaximum: TimeInterval, selfTimer: TimeInterval, npf: TimeInterval?) {
        perFrame = plan.subExposure
        self.cameraMaximum = cameraMaximum
        frames = plan.frames
        integration = plan.integration
        sequence = max(0, selfTimer) + plan.duration
        starTrailLimit = npf
    }
}

/// One still size the camera format offers, with what a frame of it stores.
public struct CaptureResolution: Sendable, Hashable, Identifiable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var id: String { "\(width)x\(height)" }
    public var pixels: Int { width * height }
    /// Whole megapixels, rounded down as cameras name them: 4032 × 3024 is
    /// "12 MP", 8064 × 6048 is "48 MP".
    public var megapixels: Int { pixels / 1_000_000 }
    public var title: String { "\(megapixels) MP" }

    /// Estimated bytes for one frame before any is measured: a DNG holds 16
    /// bits per pixel (`CapturePlan.estimatedRawBytes`); HEIC is about 0.35
    /// bytes per pixel.
    public func estimatedFrameBytes(raw: Bool) -> Int64 {
        raw ? CapturePlan.estimatedRawBytes(width: width, height: height) : CapturePlan.estimatedHEICBytes(width: width, height: height)
    }

    /// The choice the screen offers: the smallest size of at least 12 MP and
    /// the largest, when they differ (12 MP and 48 MP on the iPhone 18 Pro Max).
    public static func choices(from sizes: [CaptureResolution]) -> [CaptureResolution] {
        let sorted = Set(sizes).sorted { $0.pixels < $1.pixels }
        guard let largest = sorted.last else { return [] }
        let twelve = sorted.first { $0.pixels >= 12_000_000 } ?? largest
        return twelve == largest ? [largest] : [twelve, largest]
    }
}

extension CapturePlan {
    /// HEIC before the first frame is measured: about 0.35 bytes per pixel.
    public static func estimatedHEICBytes(width: Int, height: Int) -> Int64 {
        Int64(Double(width * height) * 0.35)
    }
}

/// A Sky-view star-trail design run on a phone. The design's interval and
/// exposure are for a dedicated camera (for example 29 s frames every 30 s);
/// a phone frame stops at `maxExposure`, so the phone keeps the design's
/// span and shoots back to back (interval = exposure) for unbroken trails.
public struct PhoneTrailPlan: Sendable, Hashable {
    public let minutes: Double
    public let interval: TimeInterval
    /// The design's span did not fit the screen's range and was clamped.
    public let clamped: Bool
    public let designMinutes: Double

    public init(design: StarTrailSequence, maxExposure: TimeInterval, minutesRange: ClosedRange<Double> = 1...120) {
        designMinutes = design.duration / 60
        let whole = designMinutes.rounded()
        minutes = min(max(whole, minutesRange.lowerBound), minutesRange.upperBound)
        clamped = minutes != whole
        interval = max(maxExposure, 0.1)
    }
}

/// The recommended first sequence (review §7): main camera, widest supported
/// aperture, the longest frame this camera allows, a modest test length,
/// 12 MP, ProRAW where offered and a short self-timer. ISO is a starting
/// point to tune from a test frame, not a best value.
public struct CapturePreset: Sendable, Hashable {
    public let exposure: TimeInterval
    public let iso: Float
    public let aperture: Float?
    /// SNR gain for the stacking plan: 3× is 9 frames.
    public let snrGain: Double
    public let selfTimer: Int
    public let raw: Bool

    public static let startingISO: Float = 3200
    public static let testSNRGain = 3.0
    public static let selfTimerSeconds = 5

    public init(maxExposure: TimeInterval, isoRange: ClosedRange<Float>, apertures: [Float], rawAvailable: Bool) {
        exposure = maxExposure
        iso = min(max(Self.startingISO, isoRange.lowerBound), isoRange.upperBound)
        aperture = apertures.min()
        snrGain = Self.testSNRGain
        selfTimer = Self.selfTimerSeconds
        raw = rawAvailable
    }
}

/// What a finished run produced, for the results view.
public struct CaptureOutcome: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case stack, trails }

    public let kind: Kind
    /// Frames the sequence planned.
    public let planned: Int
    /// Frames written to disk (every one is kept).
    public let saved: Int
    /// Frames in the stack: aligned on stars, or combined as shot.
    public let used: Int
    /// Set when the stack fell back to unaligned (too few stars).
    public let unalignedReason: String?
    /// Shutter-open total of the frames used.
    public let integration: TimeInterval

    public init(kind: Kind, planned: Int, saved: Int, used: Int, unalignedReason: String?, integration: TimeInterval) {
        self.kind = kind
        self.planned = planned
        self.saved = saved
        self.used = min(used, saved)
        self.unalignedReason = unalignedReason
        self.integration = integration
    }

    /// Saved but left out: moved, repeated, or not aligned on stars.
    public var rejected: Int { saved - used }
    public var isUnaligned: Bool { kind == .stack && unalignedReason != nil }
    /// Frames aligned on stars; nil for trails and unaligned stacks, where nothing was aligned.
    public var aligned: Int? { kind == .stack && unalignedReason == nil ? used : nil }
}
