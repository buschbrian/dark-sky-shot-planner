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

/// Hour-by-hour conditions under the night strip: cloud low/mid/high per model,
/// AOD, transparency, wind gust and dew spread. Brighter cells are worse; an
/// hour with no value is left empty and a row with no data reads unavailable.
struct ConditionsStripChart: View {
    let rows: [StripRow]
    let span: TimeWindow
    let darkness: TimeWindow?
    let timeZone: TimeZone
    let now: Date
    let loading: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        SectionCard("Conditions by hour") {
            chart
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Conditions by hour")
                .accessibilityValue(summary)
                .accessibilityIdentifier("tonight.conditionsStrip")
            if sources.isEmpty {
                ProvenanceChip(info: SourceInfo(source: loading ? "checking" : "no source", freshness: .unavailable), now: now)
            } else {
                ForEach(sources, id: \.self) { ProvenanceChip(info: $0, now: now) }
            }
            MoreInfo(title: "How to read this") {
                Text("Brighter cells are worse: more cloud, haze or wind, or a dew spread under 4 °C. The shaded band is astronomical darkness.")
                Text("A row marked – is unavailable: no value, never clear. Empty cells are hours a model does not cover.")
            }
        }
    }

    @ScaledMetric(relativeTo: .caption2) private var rowHeight = 18.0
    private static let axisHeight = 24.0

    private var chart: some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(rows) { row in
                    Text(row.unavailableReason == nil ? row.title : "\(row.title) –")
                        .font(.caption2)
                        .foregroundStyle(row.unavailableReason == nil ? palette.primary : palette.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: rowHeight)
                }
            }
            .fixedSize()
            grid
        }
        .frame(height: CGFloat(rows.count) * rowHeight + Self.axisHeight)
    }

    /// Row i fills [i + 0.1, i + 0.9] on a numeric axis, first row at the top.
    private var grid: some View {
        Chart {
            if let d = darkness {
                RectangleMark(
                    xStart: .value("Time", d.start), xEnd: .value("Time", d.end),
                    yStart: .value("Row", 0.0), yEnd: .value("Row", Double(rows.count)))
                    .foregroundStyle(palette.data.darkness)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let top = Double(rows.count - index)
                ForEach(row.points.filter { $0.v != nil && $0.t > span.start.addingTimeInterval(-1800) && $0.t < span.end.addingTimeInterval(1800) }, id: \.t) { p in
                    RectangleMark(
                        xStart: .value("Time", max(p.t.addingTimeInterval(-1800), span.start)),
                        xEnd: .value("Time", min(p.t.addingTimeInterval(1800), span.end)),
                        yStart: .value("Row", top - 0.9),
                        yEnd: .value("Row", top - 0.1))
                        .foregroundStyle(palette.data.cell.opacity(0.08 + 0.87 * badness(row, p.v!)))
                }
            }
            if now >= span.start && now <= span.end {
                RuleMark(x: .value("Now", now)).foregroundStyle(palette.primary.opacity(0.7))
            }
        }
        .chartXScale(domain: span.start...span.end)
        .chartYScale(domain: 0...Double(max(rows.count, 1)))
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXAxis { DSChart.hourAxis(palette) }
        .chartPlotStyle { $0.background(palette.data.twilight.opacity(0.35)).clipped() }
        .environment(\.timeZone, timeZone)
        .overlay {
            if loading && rows.allSatisfy({ $0.points.isEmpty }) {
                Text("Checking conditions…").font(.caption).foregroundStyle(palette.secondary)
            }
        }
    }

    /// 0 is harmless, 1 is as bad as the scale shows.
    private func badness(_ row: StripRow, _ v: Double) -> Double {
        let x: Double = switch row.kind {
        case .cloudLow, .cloudMid, .cloudHigh: v / 100
        case .aerosol: v / 0.3
        case .transparency: (v - 1) / 7
        case .wind: v / 50
        case .dewSpread: 1 - v / 8
        }
        return min(max(x, 0), 1)
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
        rows.map { row in
            guard row.unavailableReason == nil else { return "\(row.title): unavailable" }
            let vs = row.points.compactMap(\.v)
            guard let lo = vs.min(), let hi = vs.max() else { return "\(row.title): unavailable" }
            return "\(row.title) \(Format.value(lo, unit: row.unit)) to \(Format.value(hi, unit: row.unit))"
        }.joined(separator: "; ")
    }
}
