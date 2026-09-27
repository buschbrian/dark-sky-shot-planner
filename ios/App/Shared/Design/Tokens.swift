import SwiftUI

/// Spacing, radii and type for every screen. Views use these instead of
/// literal numbers so cards, rows and headers line up across tabs.
enum DS {
    /// A 4-point spacing scale.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Screen edge inset and the gap between cards.
        static let screen: CGFloat = 16
        static let cardGap: CGFloat = 12
        /// Inside a card.
        static let card: CGFloat = 16
    }

    enum Radius {
        /// Keys, fields, small buttons.
        static let control: CGFloat = 10
        /// Cards and grouped sections.
        static let card: CGFloat = 16
        /// Night bar and scrubber track.
        static let bar: CGFloat = 4
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let focus: CGFloat = 1.5
    }

    /// The minimum tappable size (HIG).
    static let minTarget: CGFloat = 44
}

/// The type scale: SF Pro throughout, SF Mono for provenance, tabular figures
/// for anything that updates. All sizes follow Dynamic Type.
extension Font {
    /// Screen and sheet titles in the navigation bar.
    static let dsNavTitle = Font.headline
    /// A card's lead line (the verdict word, a place name).
    static let dsTitle = Font.title3.weight(.semibold)
    static let dsHeadline = Font.headline
    static let dsBody = Font.body
    static let dsCallout = Font.subheadline
    static let dsFootnote = Font.footnote
    /// A secondary value on a tile or row.
    static let dsMetric = Font.title3.weight(.medium).monospacedDigit()
    static let dsMetricUnit = Font.subheadline.weight(.medium)
    /// Source · model · run · age: the instrument readout.
    static let dsData = Font.system(.caption, design: .monospaced)
    /// Section labels ("SKY TONIGHT"); pair with `.eyebrow()`.
    static let dsEyebrow = Font.caption.weight(.semibold)
    /// Times and coordinates in running text.
    static let dsNumber = Font.body.monospacedDigit()
}

extension View {
    /// A small uppercase section label in the secondary color.
    func eyebrow(_ palette: Palette) -> some View {
        font(.dsEyebrow)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(palette.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The hero number: large, medium weight, tabular, scales with Dynamic Type.
struct DisplayNumber: View {
    let value: String
    let unit: String
    var color: Color?
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var size = 60

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Text(value)
                .font(.system(size: size, weight: .medium).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(unit)
                .font(.title3.weight(.medium))
                .foregroundStyle(palette.secondary)
        }
        .foregroundStyle(color ?? palette.primary)
    }
}
