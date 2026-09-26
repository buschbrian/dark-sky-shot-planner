public import Foundation

/// What Tonight's night strip draws: sun, moon and GC altitude over the night,
/// with the darkness window and moon-free band from the same `NightReport`.
public struct NightStrip: Sendable, Hashable {
    public static let step: TimeInterval = 10 * 60

    public let span: TimeWindow
    /// Apparent (refracted) altitude, so 0° is where it rises and sets.
    public let sun: [SkySample]
    public let moon: [SkySample]
    /// Geometric, like the planner's GC numbers.
    public let galacticCenter: [SkySample]
    public let darkness: TimeWindow?
    public let moonFree: [TimeWindow]

    /// Two hours either side of astronomical darkness; without darkness, 18:00
    /// to 07:00 around the planning evening (21:00 local).
    public static func span(for report: NightReport, evening: Date) -> TimeWindow {
        if let d = report.darkness {
            return TimeWindow(start: floor(d.start.addingTimeInterval(-2 * 3600)), end: ceil(d.end.addingTimeInterval(2 * 3600)))
        }
        return TimeWindow(start: evening.addingTimeInterval(-3 * 3600), end: evening.addingTimeInterval(10 * 3600))
    }

    public static func build(
        report: NightReport, observer: Observer, evening: Date
    ) throws(AstronomyError) -> NightStrip {
        let span = span(for: report, evening: evening)
        func series(_ object: SkyObject, _ refraction: Refraction) throws(AstronomyError) -> [SkySample] {
            try SkyPositions.series(of: object, from: span.start, to: span.end, step: step, observer: observer, refraction: refraction)
        }
        return NightStrip(
            span: span,
            sun: try series(.sun, .normal),
            moon: try series(.moon, .normal),
            galacticCenter: try series(.galacticCenter, .none),
            darkness: report.darkness,
            moonFree: report.moonFreeWindows.map { TimeWindow(start: $0.start, end: $0.end) })
    }

    static func floor(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / step).rounded(.down) * step)
    }

    static func ceil(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / step).rounded(.up) * step)
    }
}

/// One row of the conditions strip under the night strip: an hourly series
/// with where it came from. Missing hours stay nil; a row with no data says why.
public struct StripRow: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case cloudLow = "Low cloud"
        case cloudMid = "Mid cloud"
        case cloudHigh = "High cloud"
        case aerosol = "AOD"
        case transparency = "Transparency"
        case wind = "Wind gust"
        case dewSpread = "Dew spread"
    }

    public let kind: Kind
    public let model: String?
    public let unit: String
    public let points: [WorkerPoint]
    /// nil when the row has data.
    public let unavailableReason: String?
    public let source: String
    public let asOfUTC: Date?

    public var id: String { "\(kind.rawValue)|\(model ?? "")" }
    public var title: String { model.map { "\(kind.rawValue) · \(StripRow.modelLabel($0))" } ?? kind.rawValue }

    public static func modelLabel(_ id: String) -> String {
        switch id {
        case "hrrr": "HRRR"
        case "gfs": "GFS"
        case "icon": "ICON"
        case "ecmwf": "ECMWF"
        case "cams_global": "CAMS"
        case "7timer_astro": "7Timer"
        case "rap_smoke": "RAP-Smoke"
        default: id
        }
    }

    /// Clouds get one row per model (disagreement is shown, not averaged);
    /// the others take the first model that has data, in the Worker's order.
    public static func rows(from response: ConditionsResponse?) -> [StripRow] {
        var out: [StripRow] = []
        for (kind, name) in [(Kind.cloudLow, "cloud_cover_low"), (.cloudMid, "cloud_cover_mid"), (.cloudHigh, "cloud_cover_high")] {
            guard let f = response?.fields[name], !f.series.isEmpty else {
                out.append(missing(kind, name, response))
                continue
            }
            out += f.series.map { row(kind, $0, f) }
        }
        for (kind, name) in [(Kind.aerosol, "aerosol_optical_depth"), (.transparency, "transparency"), (.wind, "wind_gust")] {
            guard let f = response?.fields[name], let s = f.series.first(where: { $0.status == .ok }) ?? f.series.first else {
                out.append(missing(kind, name, response))
                continue
            }
            out.append(row(kind, s, f))
        }
        out.append(dewSpread(response))
        return out
    }

    static func row(_ kind: Kind, _ s: WorkerSeries, _ f: WorkerField) -> StripRow {
        let ok = s.status == .ok && s.values.contains { $0.v != nil }
        return StripRow(
            kind: kind, model: s.model, unit: f.unit, points: ok ? s.values : [],
            unavailableReason: ok ? nil : (s.reason ?? f.reason ?? "no values"),
            source: f.source, asOfUTC: ok ? s.asOfUTC : nil)
    }

    static func missing(_ kind: Kind, _ name: String, _ response: ConditionsResponse?) -> StripRow {
        let f = response?.fields[name]
        return StripRow(
            kind: kind, model: nil, unit: f?.unit ?? "", points: [],
            unavailableReason: response == nil ? "no conditions data" : (f?.reason ?? "not in the response"),
            source: f?.source ?? "—", asOfUTC: nil)
    }

    /// Temperature minus dew point for the first model with both, hour by hour.
    static func dewSpread(_ response: ConditionsResponse?) -> StripRow {
        guard let temp = response?.fields["temperature"], let dew = response?.fields["dew_point"] else {
            return missing(.dewSpread, "dew_point", response)
        }
        for t in temp.series where t.status == .ok {
            guard let d = dew.series.first(where: { $0.model == t.model && $0.status == .ok }) else { continue }
            let byTime = Dictionary(d.values.map { ($0.t, $0.v) }, uniquingKeysWith: { a, _ in a })
            let points = t.values.map { p in
                WorkerPoint(t: p.t, v: p.v.flatMap { tv in byTime[p.t].flatMap { $0 }.map { tv - $0 } })
            }
            guard points.contains(where: { $0.v != nil }) else { continue }
            let asOf = [t.asOfUTC, d.asOfUTC].compactMap(\.self).min()
            return StripRow(kind: .dewSpread, model: t.model, unit: "°C", points: points, unavailableReason: nil,
                            source: temp.source, asOfUTC: asOf)
        }
        let reason = [temp.reason, dew.reason].compactMap(\.self).first ?? "no model has both temperature and dew point"
        return StripRow(kind: .dewSpread, model: nil, unit: "°C", points: [], unavailableReason: reason,
                        source: temp.source, asOfUTC: nil)
    }
}
