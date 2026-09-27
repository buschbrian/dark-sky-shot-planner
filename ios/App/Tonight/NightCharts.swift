import Charts
import SkyCore
import SwiftUI

/// Sun, moon and GC altitude over the night: astronomical darkness shaded, the
/// moon-free windows as a band along the bottom. Series differ by dash as well
/// as color (`DSChart.Body`), so field mode stays readable.
struct NightStripChart: View {
    let strip: NightStrip
    let timeZone: TimeZone
    let now: Date
    let gcThreshold: Double?
    @Environment(\.palette) private var palette

    private static let floor = -20.0
    private static let ceiling = 90.0

    var body: some View {
        SectionCard("Altitude tonight") {
            chart
                .frame(height: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Altitude tonight")
                .accessibilityValue(summary)
                .accessibilityIdentifier("tonight.nightStrip")
            key
        }
    }

    private var chart: some View {
        Chart {
            if let d = strip.darkness {
                RectangleMark(
                    xStart: .value("Time", d.start), xEnd: .value("Time", d.end),
                    yStart: .value("Altitude", Self.floor), yEnd: .value("Altitude", Self.ceiling))
                    .foregroundStyle(palette.data.darkness)
            }
            ForEach(Array(strip.moonFree.enumerated()), id: \.offset) { _, w in
                RectangleMark(
                    xStart: .value("Time", w.start), xEnd: .value("Time", w.end),
                    yStart: .value("Altitude", Self.floor), yEnd: .value("Altitude", Self.floor + 5))
                    .foregroundStyle(palette.data.moonFree)
            }
            RuleMark(y: .value("Horizon", 0))
                .foregroundStyle(palette.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let gcThreshold {
                RuleMark(y: .value("GC useful", gcThreshold))
                    .foregroundStyle(palette.data.galacticCenter.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            series(.sun, strip.sun)
            series(.moon, strip.moon)
            series(.galacticCenter, strip.galacticCenter)
            if now >= strip.span.start && now <= strip.span.end {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(palette.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: strip.span.start...strip.span.end)
        .chartYScale(domain: Self.floor...Self.ceiling)
        .chartLegend(.hidden)
        .chartXAxis { DSChart.hourAxis(palette) }
        .chartYAxis { DSChart.degreeAxis(palette, values: [0, 30, 60, 90]) }
        .chartPlotStyle { $0.background(palette.data.twilight.opacity(0.35)).clipped() }
        .environment(\.timeZone, timeZone)
    }

    private func series(_ body: DSChart.Body, _ samples: [SkySample]) -> some ChartContent {
        ForEach(samples, id: \.date) { s in
            LineMark(
                x: .value("Time", s.date),
                y: .value("Altitude", max(s.position.altitudeDeg, Self.floor - 1)),
                series: .value("Body", body.rawValue))
                .foregroundStyle(body.color(palette))
                .lineStyle(body.line)
                .interpolationMethod(.monotone)
        }
    }

    private var key: some View {
        ViewThatFits {
            HStack(spacing: DS.Space.m) { keyItems }
            VStack(alignment: .leading, spacing: DS.Space.xs) { keyItems }
        }
        .font(.caption)
        .foregroundStyle(palette.secondary)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var keyItems: some View {
        SeriesKey(.moon)
        SeriesKey(.galacticCenter)
        SeriesKey(.sun)
        HStack(spacing: DS.Space.xs) {
            RoundedRectangle(cornerRadius: 2).fill(palette.data.moonFree).frame(width: 16, height: 6)
            Text("Moon-free")
        }
    }

    private var summary: String {
        var parts: [String] = []
        if let d = strip.darkness {
            parts.append("Astronomical darkness \(Format.clock(d.start, timeZone)) to \(Format.clock(d.end, timeZone))")
        }
        for w in strip.moonFree {
            parts.append("moon-free \(Format.clock(w.start, timeZone)) to \(Format.clock(w.end, timeZone))")
        }
        if let moonMax = strip.moon.max(by: { $0.position.altitudeDeg < $1.position.altitudeDeg }), moonMax.position.altitudeDeg > 0 {
            parts.append("moon highest \(Int(moonMax.position.altitudeDeg))° at \(Format.clock(moonMax.date, timeZone))")
        } else {
            parts.append("moon below the horizon")
        }
        if let gcMax = strip.galacticCenter.max(by: { $0.position.altitudeDeg < $1.position.altitudeDeg }), gcMax.position.altitudeDeg > 0 {
            parts.append("Galactic Center highest \(Int(gcMax.position.altitudeDeg))° at \(Format.clock(gcMax.date, timeZone))")
        } else {
            parts.append("Galactic Center below the horizon")
        }
        return parts.joined(separator: "; ")
    }
}

/// Hour-by-hour conditions, one readable row per factor (review §D Tonight 6):
/// cloud (the worst model and layer each hour), haze, wind gust and dew
/// spread. Brighter cells are worse; the row says the worst value, when and
/// from which model; every model's own range is one tap away. An hour with no
/// value is left empty and a factor with no data reads unavailable. The
/// height is the same before and after the data arrives.
struct ConditionsStripChart: View {
    let rows: [StripRow]
    let span: TimeWindow
    let darkness: TimeWindow?
    let timeZone: TimeZone
    let now: Date
    let loading: Bool
    @Environment(\.palette) private var palette

    private var factors: [FactorStrip] { FactorStrip.rows(from: rows) }

    var body: some View {
        SectionCard("Conditions by hour") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                let all = factors
                ForEach(Array(all.enumerated()), id: \.element.id) { i, f in
                    row(f, axis: i == all.count - 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Conditions by hour")
            .accessibilityValue(summary)
            .accessibilityIdentifier("tonight.conditionsStrip")
            if sources.isEmpty {
                ProvenanceChip(info: SourceInfo(source: loading ? "checking" : "no source", freshness: .unavailable), now: now)
            } else {
                ForEach(sources, id: \.self) { ProvenanceChip(info: $0, now: now) }
            }
            MoreInfo(title: "Every model", id: "tonight.conditionsModels") {
                ForEach(rows) { r in
                    Text(modelLine(r)).font(.dsData).foregroundStyle(palette.secondary)
                }
                Text("Brighter cells are worse: more cloud, haze or wind, or a dew spread under 4 °C. The shaded band is astronomical darkness. Cloud shows the worst model and layer each hour, never an average.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
            }
        }
    }

    @ScaledMetric(relativeTo: .caption) private var cellHeight = 14.0

    private func row(_ f: FactorStrip, axis: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title(f)
                    Spacer(minLength: DS.Space.s)
                    detail(f)
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    title(f)
                    detail(f)
                }
            }
            cells(f, axis: axis)
                .frame(height: cellHeight + (axis ? 22 : 0))
        }
    }

    private func title(_ f: FactorStrip) -> some View {
        Text(f.kind.rawValue).font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
    }

    private func detail(_ f: FactorStrip) -> some View {
        Text(worstText(f))
            .font(.dsFootnote)
            .foregroundStyle(f.points.isEmpty ? palette.tertiary : palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func worstText(_ f: FactorStrip) -> String {
        if f.points.isEmpty { return loading ? "checking…" : Voice.unavailable }
        guard let w = f.worst(within: darkness ?? span) ?? f.worst(within: span) else { return "none in the night" }
        var text = "worst \(Format.value(w.v, unit: f.unit)) at \(Format.clock(w.t, timeZone))"
        if let m = w.model { text += " (\(StripRow.modelLabel(m)))" }
        return text
    }

    private func cells(_ f: FactorStrip, axis: Bool) -> some View {
        Chart {
            if let d = darkness {
                RectangleMark(xStart: .value("Time", d.start), xEnd: .value("Time", d.end),
                              yStart: .value("Row", 0.0), yEnd: .value("Row", 1.0))
                    .foregroundStyle(palette.data.darkness)
            }
            ForEach(f.points.filter { $0.t > span.start.addingTimeInterval(-1800) && $0.t < span.end.addingTimeInterval(1800) }, id: \.t) { p in
                RectangleMark(
                    xStart: .value("Time", max(p.t.addingTimeInterval(-1800), span.start)),
                    xEnd: .value("Time", min(p.t.addingTimeInterval(1800), span.end)),
                    yStart: .value("Row", 0.1), yEnd: .value("Row", 0.9))
                    .foregroundStyle(palette.data.cell.opacity(0.08 + 0.87 * f.badness(p.v)))
            }
            if now >= span.start && now <= span.end {
                RuleMark(x: .value("Now", now)).foregroundStyle(palette.primary.opacity(0.7))
            }
        }
        .chartXScale(domain: span.start...span.end)
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXAxis { if axis { DSChart.hourAxis(palette) } }
        .chartXAxis(axis ? .automatic : .hidden)
        .chartPlotStyle { $0.background(palette.data.twilight.opacity(0.35)).clipped() }
        .environment(\.timeZone, timeZone)
    }

    private func modelLine(_ r: StripRow) -> String {
        guard r.unavailableReason == nil else { return "\(r.title): \(Voice.unavailable)" }
        let vs = r.points.compactMap(\.v)
        guard let lo = vs.min(), let hi = vs.max() else { return "\(r.title): \(Voice.unavailable)" }
        return "\(r.title) \(Format.value(lo, unit: r.unit)) to \(Format.value(hi, unit: r.unit))"
    }

    /// One chip per source: its models and the oldest input's age.
    private var sources: [SourceInfo] {
        let groups = Dictionary(grouping: rows.filter { $0.unavailableReason == nil }, by: \.source)
        return groups.keys.sorted().map { source in
            let rs = groups[source]!
            let models = Set(rs.compactMap(\.model)).map(StripRow.modelLabel).sorted().joined(separator: ", ")
            return SourceInfo(source: source, model: models.isEmpty ? nil : models, asOf: rs.compactMap(\.asOfUTC).min())
        }
    }

    private var summary: String {
        factors.map { f in
            f.points.isEmpty ? "\(f.kind.rawValue): unavailable" : "\(f.kind.rawValue): \(worstText(f))"
        }.joined(separator: "; ")
    }
}

/// One factor's hourly worst value across models (and, for cloud, layers).
struct FactorStrip: Identifiable {
    enum Kind: String, CaseIterable {
        case cloud = "Cloud", haze = "Haze (AOD)", wind = "Wind gust", dew = "Dew spread"
    }

    struct Point {
        let t: Date
        let v: Double
        let model: String?
    }

    let kind: Kind
    let unit: String
    let points: [Point]
    var id: String { kind.rawValue }

    /// 0 is harmless, 1 is as bad as the scale shows.
    func badness(_ v: Double) -> Double {
        let x: Double = switch kind {
        case .cloud: v / 100
        case .haze: v / 0.3
        case .wind: v / 50
        case .dew: 1 - v / 8
        }
        return min(max(x, 0), 1)
    }

    /// The worst hour inside `window`.
    func worst(within window: TimeWindow) -> Point? {
        let inside = points.filter { $0.t >= window.start && $0.t <= window.end }
        return kind == .dew ? inside.min { $0.v < $1.v } : inside.max { $0.v < $1.v }
    }

    /// Always four rows, in this order, whatever arrived.
    static func rows(from strip: [StripRow]) -> [FactorStrip] {
        Kind.allCases.map { kind in
            let members = strip.filter { r in
                switch (kind, r.kind) {
                case (.cloud, .cloudLow), (.cloud, .cloudMid), (.cloud, .cloudHigh): true
                case (.haze, .aerosol), (.wind, .wind), (.dew, .dewSpread): true
                default: false
                }
            }.filter { $0.unavailableReason == nil }
            var byTime: [Date: Point] = [:]
            for r in members {
                for p in r.points {
                    guard let v = p.v else { continue }
                    if let old = byTime[p.t], kind == .dew ? old.v <= v : old.v >= v { continue }
                    byTime[p.t] = Point(t: p.t, v: v, model: r.model)
                }
            }
            let unit = members.first?.unit ?? (kind == .cloud ? "%" : "")
            return FactorStrip(kind: kind, unit: unit, points: byTime.values.sorted { $0.t < $1.t })
        }
    }
}
