import Charts
import SkyCore
import SwiftUI

/// One look for every Swift Charts chart: recessive grid, data-font labels,
/// the same darkness shading, and the same sun, moon and Galactic Center
/// colors and dashes on Tonight, Week and Spots.
enum DSChart {
    /// Hour ticks every `every` hours, labelled in the locale's hour style.
    static func hourAxis(_ palette: Palette, every: Int = 2) -> some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: every)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(palette.data.grid)
            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), centered: false)
                .font(.dsData)
                .foregroundStyle(palette.data.axisLabel)
        }
    }

    /// Altitude in degrees on the leading edge.
    static func degreeAxis(_ palette: Palette, values: [Double]) -> some AxisContent {
        AxisMarks(position: .leading, values: values) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(palette.data.grid)
            AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0))°") }
                .font(.dsData)
                .foregroundStyle(palette.data.axisLabel)
        }
    }

    enum Body: String, CaseIterable {
        case sun = "Sun", moon = "Moon", galacticCenter = "GC"

        func color(_ p: Palette) -> Color {
            switch self {
            case .sun: p.data.sun
            case .moon: p.data.moon
            case .galacticCenter: p.data.galacticCenter
            }
        }

        var dash: [CGFloat] {
            switch self {
            case .sun: DataPalette.sunDash
            case .moon: DataPalette.moonDash
            case .galacticCenter: DataPalette.gcDash
            }
        }

        var line: StrokeStyle { StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash) }
    }
}

extension Palette {
    /// Map azimuth lines and chart series share these.
    func color(for object: SkyObject) -> Color {
        switch object {
        case .sun: data.sun
        case .galacticCenter: data.galacticCenter
        default: data.moon
        }
    }
}

/// A line-and-name key entry drawn with the series' own stroke.
struct SeriesKey: View {
    let body_: DSChart.Body
    @Environment(\.palette) private var palette

    init(_ body: DSChart.Body) { self.body_ = body }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Path { p in
                p.move(to: CGPoint(x: 1, y: 4))
                p.addLine(to: CGPoint(x: 17, y: 4))
            }
            .stroke(body_.color(palette), style: body_.line)
            .frame(width: 18, height: 8)
            Text(body_.rawValue)
        }
    }
}
