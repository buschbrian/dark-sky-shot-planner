import Charts
import SkyCore
import SwiftUI

/// Sun, moon and GC altitude over the night, astronomical darkness shaded and
/// the moon-free band along the bottom. Every color comes from the palette;
/// series differ by dash pattern as well as color, so field mode stays readable.
struct NightStripChart: View {
    let strip: NightStrip
    let timeZone: TimeZone
    let now: Date
    let gcThreshold: Double?
    @Environment(\.palette) private var palette

    private static let floor = -20.0
    private static let ceiling = 90.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Night strip")
                .font(.headline)
                .foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)
            chart
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Night strip")
                .accessibilityValue(summary)
                .accessibilityIdentifier("tonight.nightStrip")
            legend
        }
        .card(palette)
    }

    private var chart: some View {
        Chart {
            if let d = strip.darkness {
                RectangleMark(
                    xStart: .value("Time", d.start), xEnd: .value("Time", d.end),
                    yStart: .value("Altitude", Self.floor), yEnd: .value("Altitude", Self.ceiling))
                    .foregroundStyle(palette.background.opacity(0.9))
            }
            ForEach(Array(strip.moonFree.enumerated()), id: \.offset) { _, w in
                RectangleMark(
                    xStart: .value("Time", w.start), xEnd: .value("Time", w.end),
                    yStart: .value("Altitude", Self.floor), yEnd: .value("Altitude", Self.floor + 5))
                    .foregroundStyle(palette.good)
            }
            RuleMark(y: .value("Horizon", 0))
                .foregroundStyle(palette.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let gcThreshold {
                RuleMark(y: .value("GC useful", gcThreshold))
                    .foregroundStyle(palette.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            series("Sun", strip.sun, color: palette.marginal, dash: [6, 3])
            series("Moon", strip.moon, color: palette.primary, dash: [])
            series("Galactic Center", strip.galacticCenter, color: palette.accent, dash: [1.5, 3])
            if now >= strip.span.start && now <= strip.span.end {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(palette.accent.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: strip.span.start...strip.span.end)
        .chartYScale(domain: Self.floor...Self.ceiling)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine().foregroundStyle(palette.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.hour(), centered: false).foregroundStyle(palette.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 30, 60, 90]) { value in
                AxisGridLine().foregroundStyle(palette.secondary.opacity(0.2))
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)°") }.foregroundStyle(palette.secondary)
            }
        }
        .chartPlotStyle { $0.background(palette.surface.opacity(0.4)).clipped() }
        .environment(\.timeZone, timeZone)
    }

    private func series(_ name: String, _ samples: [SkySample], color: Color, dash: [CGFloat]) -> some ChartContent {
        ForEach(samples, id: \.date) { s in
            LineMark(
                x: .value("Time", s.date),
                y: .value("Altitude", max(s.position.altitudeDeg, Self.floor - 1)),
                series: .value("Body", name))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
                .interpolationMethod(.monotone)
        }
    }

    private var legend: some View {
        ViewThatFits {
            HStack(spacing: 12) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .font(.caption)
        .foregroundStyle(palette.secondary)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var legendItems: some View {
        swatch("Sun", palette.marginal, dash: [6, 3])
        swatch("Moon", palette.primary, dash: [])
        swatch("GC", palette.accent, dash: [1.5, 3])
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(palette.good).frame(width: 16, height: 6)
            Text("Moon-free")
        }
    }

    private func swatch(_ name: String, _ color: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 4) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 4))
                p.addLine(to: CGPoint(x: 18, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
            .frame(width: 18, height: 8)
            Text(name)
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
/// AOD, transparency, wind gust and dew spread. Darker cells are worse; an
/// hour with no value is left empty and a row with no data says "unavailable".
struct ConditionsStripChart: View {
    let rows: [StripRow]
    let span: TimeWindow
    let darkness: TimeWindow?
    let timeZone: TimeZone
    let now: Date
    let loading: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions by hour")
                .font(.headline)
                .foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)
            chart
                .frame(height: CGFloat(rows.count) * 18 + 30)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Conditions by hour")
                .accessibilityValue(summary)
                .accessibilityIdentifier("tonight.conditionsStrip")
            Text("Brighter cells are worse: more cloud, haze or wind, or a dew spread under 4 °C. Empty rows are unavailable, never clear.")
                .font(.caption)
                .foregroundStyle(palette.secondary)
            Text(sources)
                .font(.caption)
                .foregroundStyle(palette.secondary)
        }
        .card(palette)
    }

    private func label(_ row: StripRow) -> String {
        row.unavailableReason == nil ? row.title : "\(row.title): unavailable"
    }

    private var chart: some View {
        Chart {
            if let d = darkness {
                RectangleMark(xStart: .value("Time", d.start), xEnd: .value("Time", d.end))
                    .foregroundStyle(palette.background.opacity(0.6))
            }
            ForEach(rows) { row in
                ForEach(row.points.filter { $0.v != nil && $0.t >= span.start.addingTimeInterval(-1800) && $0.t <= span.end.addingTimeInterval(1800) }, id: \.t) { p in
                    RectangleMark(
                        xStart: .value("Time", p.t.addingTimeInterval(-1800)),
                        xEnd: .value("Time", p.t.addingTimeInterval(1800)),
                        y: .value("Row", label(row)),
                        height: .ratio(0.8))
                        .foregroundStyle(palette.primary.opacity(0.08 + 0.87 * badness(row, p.v!)))
                }
            }
            if now >= span.start && now <= span.end {
                RuleMark(x: .value("Now", now)).foregroundStyle(palette.accent.opacity(0.7))
            }
        }
        .chartXScale(domain: span.start...span.end)
        .chartYScale(domain: rows.map(label))
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine().foregroundStyle(palette.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.hour()).foregroundStyle(palette.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(palette.secondary)
            }
        }
        .environment(\.timeZone, timeZone)
        .overlay {
            if loading && rows.allSatisfy({ $0.points.isEmpty }) {
                Text("Fetching conditions…").font(.caption).foregroundStyle(palette.secondary)
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

    private var sources: String {
        let groups = Dictionary(grouping: rows.filter { $0.unavailableReason == nil }, by: \.source)
        guard !groups.isEmpty else {
            return loading ? "Sources: fetching…" : "Sources: none available"
        }
        return "Sources: " + groups.keys.sorted().map { source in
            let rs = groups[source]!
            let models = Set(rs.compactMap(\.model)).map(StripRow.modelLabel).sorted().joined(separator: ", ")
            let oldest = rs.compactMap(\.asOfUTC).min()
            let age = oldest.map { " · " + Format.age(now.timeIntervalSince($0)) } ?? ""
            return "\(source) (\(models))\(age)"
        }.joined(separator: "; ")
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
