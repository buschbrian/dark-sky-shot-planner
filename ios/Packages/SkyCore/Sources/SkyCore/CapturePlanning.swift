public import Foundation

/// The iPhone's own camera as an M10 gear profile, derived from a captured
/// frame's EXIF (ADR-0011 §4), so the NPF and trail limits apply to it.
/// Crop factor = 35 mm-equivalent ÷ real focal length; the sensor diagonal is
/// 43.27 mm ÷ crop (EXIF FocalLengthIn35mmFilm scales by the diagonal; CIPA
/// DC-008), split by the image's aspect ratio. Pixel pitch follows from the
/// image width, so it is the pitch of the delivered image, not the photosite.
public enum PhoneGear {
    public static func profiles(
        name: String, focalLengthMM: Double, focalLength35mmEquivalent: Double,
        fNumber: Double, widthPx: Int, heightPx: Int
    ) throws(ExposureError) -> (camera: CameraProfile, lens: LensProfile) {
        let f = try requirePositive(.focalLength, focalLengthMM)
        let f35 = try requirePositive(.focalLength, focalLength35mmEquivalent)
        let resolution = try PixelResolution(widthPx: max(widthPx, heightPx), heightPx: min(widthPx, heightPx))
        let crop = f35 / f
        let diagonal = CameraProfile.fullFrameDiagonalMM / crop
        let w = Double(resolution.widthPx), h = Double(resolution.heightPx)
        let d = (w * w + h * h).squareRoot()
        let camera = try CameraProfile(name: name, sensorWidthMM: diagonal * w / d, sensorHeightMM: diagonal * h / d,
                                       resolution: resolution)
        let lens = try LensProfile(name: name, focalLengthMM: f, maxFNumber: fNumber)
        return (camera, lens)
    }
}

/// Before a sequence starts: how long it takes, what it stores, and what it
/// may cost in battery, with every assumption visible (ADR-0011 consequences).
public struct CapturePlan: Sendable, Hashable {
    public let frames: Int
    public let subExposure: TimeInterval
    /// Idle time between frames (write-out, thermal pauses excluded).
    public let gap: TimeInterval
    public let bytesPerFrame: Int64
    /// Extra scratch per frame while a sigma-clipped stack is built (decoded
    /// 16-bit RGB), freed afterwards; 0 for maximum/mean stacks, which stream.
    public let workingBytesPerFrame: Int64
    public let stackBytes: Int64

    public init(frames: Int, subExposure: TimeInterval, gap: TimeInterval, bytesPerFrame: Int64,
                workingBytesPerFrame: Int64, stackBytes: Int64) throws(ExposureError) {
        guard frames >= 1 else { throw .invalid(.frames, Double(frames)) }
        self.frames = frames
        self.subExposure = try requirePositive(.exposure, subExposure)
        self.gap = try require(.buffer, gap) { $0 >= 0 }
        self.bytesPerFrame = bytesPerFrame
        self.workingBytesPerFrame = workingBytesPerFrame
        self.stackBytes = stackBytes
    }

    /// Frames × (exposure + gap).
    public var duration: TimeInterval { Double(frames) * (subExposure + gap) }
    /// Shutter-open time.
    public var integration: TimeInterval { Double(frames) * subExposure }
    public var storedBytes: Int64 { Int64(frames) * bytesPerFrame + stackBytes }
    /// The most the sequence needs at once: frames, the stack, and the working space.
    public var peakBytes: Int64 { storedBytes + Int64(frames) * workingBytesPerFrame }

    /// Keeps a reserve (1 GB) free for the system.
    public static let storageReserveBytes: Int64 = 1 << 30

    public func fits(freeBytes: Int64) -> Bool { peakBytes + Self.storageReserveBytes <= freeBytes }

    /// Frames that fit in `freeBytes` after the reserve.
    public func maxFrames(freeBytes: Int64) -> Int {
        let perFrame = bytesPerFrame + workingBytesPerFrame
        guard perFrame > 0 else { return Int.max }
        return Int(max(0, (freeBytes - Self.storageReserveBytes - stackBytes) / perFrame))
    }

    /// Estimated size of one frame before any has been captured: 16-bit
    /// samples for a Bayer DNG (one per photosite) plus 2 % container; the
    /// first real frame's file size replaces this.
    public static func estimatedRawBytes(width: Int, height: Int) -> Int64 {
        Int64(Double(width * height * 2) * 1.02)
    }

    /// Decoded 16-bit RGB, the stacker's working copy of one frame.
    public static func rgb16Bytes(width: Int, height: Int) -> Int64 { Int64(width * height * 3 * 2) }
}

/// Battery drain measured on this phone, not assumed: a straight-line fit
/// of level against time once the level has moved. Until then it says so.
public struct BatteryTrend: Sendable, Hashable {
    public struct Sample: Sendable, Hashable {
        public let time: TimeInterval
        /// 0...1, as UIDevice reports it.
        public let level: Double

        public init(time: TimeInterval, level: Double) {
            self.time = time
            self.level = level
        }
    }

    public private(set) var samples: [Sample] = []
    /// A fit needs this long a span and this much change (UIDevice reports whole percent).
    public var minimumSpan: TimeInterval = 300
    public var minimumDrop = 0.02

    public init() {}

    public mutating func add(_ sample: Sample) {
        guard sample.level >= 0, sample.level <= 1 else { return }
        if let last = samples.last, sample.level > last.level + 0.005 { samples.removeAll() } // charging: restart
        samples.append(sample)
        if samples.count > 720 { samples.removeFirst(samples.count - 720) }
    }

    /// Fraction of a full battery used per hour; nil until measured.
    public var drainPerHour: Double? {
        guard let first = samples.first, let last = samples.last,
              last.time - first.time >= minimumSpan, first.level - last.level >= minimumDrop else { return nil }
        let n = Double(samples.count)
        let mt = samples.reduce(0) { $0 + $1.time } / n, ml = samples.reduce(0) { $0 + $1.level } / n
        var num = 0.0, den = 0.0
        for s in samples {
            num += (s.time - mt) * (s.level - ml)
            den += (s.time - mt) * (s.time - mt)
        }
        guard den > 0 else { return nil }
        let slope = num / den
        return slope < 0 ? -slope * 3600 : nil
    }

    /// Battery fraction a sequence of `duration` would use at the measured rate.
    public func estimatedUse(duration: TimeInterval) -> Double? {
        drainPerHour.map { $0 * duration / 3600 }
    }
}

/// What the capture loop does at each thermal state (Apple, "Responding to
/// power notifications"): carry on, cool down between frames, or stop and
/// keep what was shot.
public enum ThermalPolicy {
    public enum Action: Sendable, Hashable {
        case proceed
        case coolDown(TimeInterval)
        case stop
    }

    public static func action(for state: ProcessInfo.ThermalState, subExposure: TimeInterval) -> Action {
        switch state {
        case .nominal, .fair: .proceed
        // A pause at least as long as the exposure halves the camera's duty cycle.
        case .serious: .coolDown(max(subExposure, 2))
        case .critical: .stop
        @unknown default: .coolDown(max(subExposure, 2))
        }
    }
}

/// Tripod check from the gyroscope: over a short window, the phone is still
/// when both the mean rotation rate and its variance are small. Thresholds
/// are proposals until checked on a tripod (owner check).
public struct StabilityMonitor: Sendable, Hashable {
    public var window: Int
    /// rad/s. A hand-held phone shows 0.02–0.1 rad/s; a tripod well under 0.01.
    public var maxMeanRate: Double
    /// (rad/s)², summed over the three axes.
    public var maxVariance: Double
    public private(set) var rates: [SIMD3<Double>] = []

    public init(window: Int = 50, maxMeanRate: Double = 0.01, maxVariance: Double = 2.5e-5) {
        self.window = window
        self.maxMeanRate = maxMeanRate
        self.maxVariance = maxVariance
    }

    public mutating func add(_ rotationRate: SIMD3<Double>) {
        rates.append(rotationRate)
        if rates.count > window { rates.removeFirst(rates.count - window) }
    }

    public mutating func reset() { rates.removeAll() }

    public var meanRate: Double? {
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0) { $0 + ($1 * $1).sum().squareRoot() } / Double(rates.count)
    }

    /// Sum of per-axis sample variances.
    public var variance: Double? {
        guard rates.count >= 2 else { return nil }
        let n = Double(rates.count)
        let mean = rates.reduce(SIMD3<Double>.zero, +) / n
        let sq = rates.reduce(SIMD3<Double>.zero) { $0 + ($1 - mean) * ($1 - mean) }
        return (sq / (n - 1)).sum()
    }

    /// Nil until the window is full.
    public var isStable: Bool? {
        guard rates.count >= window, let m = meanRate, let v = variance else { return nil }
        return m <= maxMeanRate && v <= maxVariance
    }
}
