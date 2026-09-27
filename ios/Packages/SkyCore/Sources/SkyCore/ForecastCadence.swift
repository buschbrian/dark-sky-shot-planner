public import Foundation

/// Which forecast points stand for one model's field over time: HRRR's native
/// 15-minute series (`WorkerField.series15Min`) where it covers, the hourly
/// series elsewhere. The verdict and the charts both read this, so a short
/// gust the Worker sent is never shown in a chart and missed by the verdict.
///
/// Rules:
/// - **Coverage:** the 15-minute points replace hourly ones from the first
///   15-minute time to the last; hourly points before and after stay. The
///   Worker ends the 15-minute series at the run + 18 h, where HRRR stops
///   publishing native 15-minute output.
/// - **Null or unavailable:** a 15-minute series that is not `ok`, is empty,
///   or has any null or non-finite value is not used at all; the hourly
///   series is, and `note` says why. A partly filled fine series is never
///   spliced, so a gap can't pass for calm.
/// - **Provenance and freshness:** only a fine series from the same model,
///   beside an `ok` hourly series, is used; the combined data is as old as
///   the older of the two (`asOfUTC`).
/// - **Weighting:** every point stands for the time nearest to it (half-way
///   to each neighbour), so a mean over mixed cadence weights a 15-minute
///   point a quarter of an hourly one (`timeWeightedMean`).
public struct CadenceSelection: Sendable, Hashable {
    /// Sorted by time, one point per time.
    public let points: [WorkerPoint]
    /// Where the 15-minute points were used; nil when only hourly was.
    public let fineSpan: TimeWindow?
    /// "15-min HRRR to 06:00Z, hourly after", or why the 15-minute series was not used.
    public let note: String?
    /// The older as-of time of the series used.
    public let asOfUTC: Date?
}

public enum ForecastCadence {
    public static func select(hourly: WorkerSeries, fine: WorkerSeries?) -> CadenceSelection {
        let hourlyPoints = sorted(hourly.values)
        func hourlyOnly(_ note: String?) -> CadenceSelection {
            CadenceSelection(points: hourlyPoints, fineSpan: nil, note: note, asOfUTC: hourly.asOfUTC)
        }
        guard let fine, fine.model == hourly.model, hourly.status == .ok else { return hourlyOnly(nil) }
        guard fine.status == .ok else {
            return hourlyOnly("15-min series unavailable (\(fine.reason ?? "no reason given")); hourly used")
        }
        let finePoints = sorted(fine.values)
        guard let first = finePoints.first?.t, let last = finePoints.last?.t else {
            return hourlyOnly(nil)
        }
        guard finePoints.allSatisfy({ $0.v.map(\.isFinite) ?? false }) else {
            return hourlyOnly("15-min series has missing values; hourly used")
        }
        let points = hourlyPoints.filter { $0.t < first } + finePoints + hourlyPoints.filter { $0.t > last }
        let asOf = [hourly.asOfUTC, fine.asOfUTC].compactMap(\.self).min()
        return CadenceSelection(
            points: points, fineSpan: TimeWindow(start: first, end: last),
            note: "15-min to \(hhmmZ(last)), hourly after", asOfUTC: asOf)
    }

    /// The selection for `field` and `model` in a response; nil when the model has no hourly series.
    public static func select(_ response: ConditionsResponse, field: String, model: String) -> CadenceSelection? {
        guard let f = response.fields[field], let hourly = f.series.first(where: { $0.model == model }) else { return nil }
        return select(hourly: hourly, fine: f.series15Min?.first { $0.model == model })
    }

    /// Mean over `windows`, each sample weighted by the part of the windows
    /// nearest to it (half-way to each neighbour; the ends mirror their one
    /// neighbour). Samples are values at instants, as Open-Meteo gives them.
    public static func timeWeightedMean(_ samples: [Date: Double], over windows: [TimeWindow]) -> Double? {
        let times = samples.keys.sorted()
        guard let only = times.first else { return nil }
        if times.count == 1 { return samples[only] }
        var sum = 0.0, weight = 0.0
        for (i, t) in times.enumerated() {
            let before = i > 0 ? times[i - 1] : t.addingTimeInterval(-times[1].timeIntervalSince(t))
            let after = i + 1 < times.count ? times[i + 1] : t.addingTimeInterval(t.timeIntervalSince(times[i - 1]))
            let lo = Date(timeIntervalSince1970: (before.timeIntervalSince1970 + t.timeIntervalSince1970) / 2)
            let hi = Date(timeIntervalSince1970: (t.timeIntervalSince1970 + after.timeIntervalSince1970) / 2)
            for w in windows {
                let overlap = min(hi, w.end).timeIntervalSince(max(lo, w.start))
                if overlap > 0 {
                    sum += samples[t]! * overlap
                    weight += overlap
                }
            }
        }
        return weight > 0 ? sum / weight : nil
    }

    static func sorted(_ values: [WorkerPoint]) -> [WorkerPoint] {
        var seen = Set<Date>()
        return values.sorted { $0.t < $1.t }.filter { seen.insert($0.t).inserted }
    }

    static func hhmmZ(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02dZ", c.hour ?? 0, c.minute ?? 0)
    }
}
