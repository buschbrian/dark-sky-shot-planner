public import Foundation

/// One hourly value; `nil` is a missing hour, never 0.
public struct HourlySample: Sendable, Hashable {
    public let time: Date
    public let value: Double?

    public init(time: Date, value: Double?) {
        self.time = time
        self.value = value
    }
}

/// One model's hourly cloud cover (%), for example a Worker `cloud_cover`
/// series. Each value is instantaneous at its time (Open-Meteo), so it stands
/// for the hour centred on it.
public struct HourlySeries: Sendable, Hashable {
    public let model: String
    public let samples: [HourlySample]

    public init(model: String, samples: [HourlySample]) {
        self.model = model
        self.samples = samples
    }

    static let sampleSpan: TimeInterval = 3600
}

/// Time-weighted mean of a series over a set of windows. Hours that are
/// missing (`nil`, non-finite, or outside the series) are left out of the
/// mean and reduce `coveredFraction`; they never count as clear. A repeated
/// time keeps its first sample.
public struct WindowMean: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// Every moment of the windows has a value.
        case complete
        /// Some of the windows has no value: `mean` covers only the rest, so
        /// treat it as incomplete data, not as a rating input.
        case partial
        /// No value anywhere in the windows.
        case unavailable
        /// There is nothing to average: no moon-free astronomical darkness.
        case noWindow
    }

    public let status: Status
    /// Mean over the covered part of the windows; nil when unavailable or no window.
    public let mean: Double?
    /// Covered time / window time, 0...1 (0 when there is no window).
    public let coveredFraction: Double

    /// The mean only when every hour of the window has data.
    public var completeMean: Double? { status == .complete ? mean : nil }

    /// Coverage within this much of the window length counts as complete
    /// (absorbs floating-point error on window edges).
    static let completeTolerance: TimeInterval = 1

    public static func of(_ series: HourlySeries, over windows: [TimeWindow]) -> WindowMean {
        let windows = windows.filter { $0.end > $0.start }
        let total = windows.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return WindowMean(status: .noWindow, mean: nil, coveredFraction: 0) }

        var seen = Set<Date>()
        var weighted = 0.0
        var covered = 0.0
        for sample in series.samples where seen.insert(sample.time).inserted {
            guard let v = sample.value, v.isFinite else { continue }
            let span = TimeWindow(
                start: sample.time.addingTimeInterval(-HourlySeries.sampleSpan / 2),
                end: sample.time.addingTimeInterval(HourlySeries.sampleSpan / 2))
            for window in windows {
                let overlap = min(span.end, window.end).timeIntervalSince(max(span.start, window.start))
                if overlap > 0 {
                    weighted += v * overlap
                    covered += overlap
                }
            }
        }
        guard covered > 0 else { return WindowMean(status: .unavailable, mean: nil, coveredFraction: 0) }
        let complete = total - covered <= completeTolerance
        return WindowMean(
            status: complete ? .complete : .partial,
            mean: weighted / covered,
            coveredFraction: complete ? 1 : covered / total)
    }
}
