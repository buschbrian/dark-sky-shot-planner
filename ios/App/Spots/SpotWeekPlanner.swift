import Foundation
import SkyCore

/// The 7-night check behind a spot's strip, its alerts and the widget. The
/// astronomy is SkyCore's planner (with the spot's skyline when it has one);
/// the verdict is SkyCore's worst-gating-factor rule over that night's
/// moon-free darkness. The Week screen owns the full outlook; this is the
/// compact per-spot version.
nonisolated enum SpotWeekPlanner {
    static let nightCount = 7
    static let config: VerdictConfig? = try? VerdictConfig.bundled()
    static let onDeviceSource = "astronomy-engine (on device)"

    struct Input: Sendable {
        let place: Place
        let latitude: Double
        let longitude: Double
        let timeZone: TimeZone
        let horizon: HorizonProfile?
    }

    @MainActor
    static func input(for spot: Spot) -> Input {
        Input(place: spot.place, latitude: spot.latitude, longitude: spot.longitude,
              timeZone: spot.place.timeZone, horizon: spot.horizonProfile)
    }

    @concurrent
    static func compute(_ input: Input, conditions: any ConditionsProviding, now: Date = .now) async -> SpotWeek {
        let first = NightDate.containing(now, in: input.timeZone)
        let dates = (0..<nightCount).map { first.adding(days: $0) }
        let observer = try? Observer(latitude: input.latitude, longitude: input.longitude)

        struct Astro: Sendable { let flat: NightReport?; let skyline: NightReport? }
        let astro: [Astro] = dates.map { date in
            guard let observer else { return Astro(flat: nil, skyline: nil) }
            let evening = date.evening(in: input.timeZone)
            let flat = try? Planner.planNight(observer, evening: evening)
            let skyline = input.horizon.flatMap { try? Planner.planNight(observer, evening: evening, horizon: $0) }
            return Astro(flat: flat, skyline: skyline)
        }

        let snapshots = await withTaskGroup(of: (Int, ConditionsSnapshot?).self) { group in
            for (i, a) in astro.enumerated() {
                // A night with no moon-free darkness is no-go on astronomy alone; skip the request.
                guard let report = a.skyline ?? a.flat, let dark = report.darkness,
                      !report.moonFreeWindows.isEmpty else { continue }
                let window = DateInterval(start: dark.start.addingTimeInterval(-3600), end: dark.end.addingTimeInterval(3600))
                group.addTask { (i, await conditions.conditions(for: input.place, window: window)) }
            }
            var out: [Int: ConditionsSnapshot] = [:]
            for await (i, s) in group { if let s { out[i] = s } }
            return out
        }

        let nights = dates.enumerated().map { i, date in
            let a = astro[i]
            let report = a.skyline ?? a.flat
            let verdict = report.flatMap { r in
                config.flatMap { try? Verdict.evaluate(night: r, conditions: snapshots[i]?.response, config: $0, now: now) }
            }
            return NightSummary(
                night: date.iso,
                moonFreeMinutes: a.flat?.moonFreeMinutes,
                skylineMoonFreeMinutes: a.skyline?.moonFreeMinutes,
                verdict: verdict.map(summary))
        }
        return SpotWeek(checkedAt: now, terrainAware: input.horizon != nil, nights: nights)
    }

    static func summary(_ v: Verdict) -> VerdictSummary {
        let f = v.limiting
        let source = f.provenance.map { p in
            [p.source, p.model].compactMap(\.self).joined(separator: " · ")
        } ?? (f.isUnavailable ? "no conditions data" : "unknown source")
        let cause: VerdictSummary.Cause = switch v.cause {
        case .rating: .rating
        case .incompleteData: .incompleteData
        case .staleData: .staleData
        }
        return VerdictSummary(
            level: v.level,
            cause: cause,
            limitingLabel: f.factor.label,
            limitingValue: f.value.map { format($0, unit: f.factor.unit) } ?? "unavailable",
            limitingSource: source,
            // On-device astronomy has no data age; only fetched data does.
            limitingAsOf: f.provenance?.source == onDeviceSource ? nil : f.provenance?.asOfUTC,
            freshness: f.freshness,
            evaluatedAt: v.evaluatedAt)
    }

    static func format(_ value: Double, unit: String) -> String {
        let number = abs(value) >= 10 || value == value.rounded()
            ? String(Int(value.rounded()))
            : String(format: "%.2f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}
