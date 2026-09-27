import SkyCore
import SwiftUI

// MARK: - Section card

/// The one grouped surface: an optional eyebrow title, then content.
struct SectionCard<Content: View, Accessory: View>: View {
    var title: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).eyebrow(palette)
                    Spacer(minLength: DS.Space.s)
                    accessory
                }
            }
            content
        }
        .padding(DS.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

extension SectionCard where Accessory == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = EmptyView()
        self.content = content()
    }
}

extension SectionCard {
    init(_ title: String?, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }
}

// MARK: - Provenance

/// Source · model · run · age · freshness for one number (ADR-0006).
struct SourceInfo: Hashable {
    var source: String
    var model: String?
    var run: Date?
    /// What the age counts from; nil for values computed on the phone.
    var asOf: Date?
    var freshness: Freshness?
    /// "last good copy", "estimated", "4 models"…
    var note: String?

    static let onDevice = SourceInfo(source: "astronomy-engine", note: Voice.onDevice)

    init(source: String, model: String? = nil, run: Date? = nil, asOf: Date? = nil,
         freshness: Freshness? = nil, note: String? = nil) {
        self.source = Voice.source(source)
        self.model = model
        self.run = run
        self.asOf = asOf
        self.freshness = freshness
        self.note = note
    }

    /// From a verdict factor's provenance; readings computed on the phone say so.
    init(_ p: SkyCore.Provenance, lastGood: Bool = false) {
        if p.source.contains("on device") {
            self = .onDevice
            return
        }
        self.init(source: p.source, model: p.model.map(StripRow.modelLabel), run: p.modelRunUTC,
                  asOf: p.asOfUTC, freshness: p.freshness, note: lastGood ? Voice.lastGood : nil)
    }

    func parts(now: Date) -> [String] {
        var parts: [String] = []
        if let model { parts.append(model) }
        parts.append(source)
        if let note { parts.append(note) }
        if let run { parts.append("run \(Voice.run(run, now: now))") }
        if let asOf { parts.append(Voice.age(of: asOf, now: now)) }
        return parts
    }

    func spoken(now: Date) -> String {
        var s = "Source: " + parts(now: now).joined(separator: ", ")
        if let freshness { s += ", \(freshness.word)" }
        return s
    }
}

/// The instrument readout under a number: "HRRR · Open-Meteo · run 18Z · 2 h old ● fresh".
/// Freshness always has a glyph; its word shows unless it is fresh.
struct ProvenanceChip: View {
    let info: SourceInfo
    var now: Date = .now
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            if let f = info.freshness {
                Image(systemName: f.symbol)
                    .imageScale(.small)
                    .foregroundStyle(color(f))
            }
            Text(text)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.dsData)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.spoken(now: now))
    }

    /// Short parts ("2 h old", "run 18Z") never break across lines.
    private var text: String {
        let parts = info.parts(now: now).map { $0.count <= 14 ? $0.replacingOccurrences(of: " ", with: "\u{00A0}") : $0 }
        var line = parts.joined(separator: " · ")
        if let f = info.freshness, f != .fresh { line += " · " + f.word.replacingOccurrences(of: " ", with: "\u{00A0}") }
        return line
    }

    private func color(_ f: Freshness) -> Color {
        switch f {
        case .fresh: palette.good
        case .aging: palette.secondary
        case .stale: palette.marginal
        case .unavailable: palette.tertiary
        }
    }
}

// MARK: - Status

/// Go / marginal / no-go, or unavailable when there is no verdict.
enum StatusLevel: Hashable {
    case go, marginal, noGo, unavailable

    init(_ level: VerdictLevel?) {
        switch level {
        case .go: self = .go
        case .marginal: self = .marginal
        case .noGo: self = .noGo
        case nil: self = .unavailable
        }
    }

    var word: String {
        switch self {
        case .go: "Go"
        case .marginal: "Marginal"
        case .noGo: "No-go"
        case .unavailable: "Unavailable"
        }
    }

    /// Shape as well as color: field mode tells levels apart by brightness only.
    var symbol: String {
        switch self {
        case .go: "checkmark.circle.fill"
        case .marginal: "minus.circle.fill"
        case .noGo: "xmark.circle.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    func color(_ p: Palette) -> Color {
        switch self {
        case .go: p.good
        case .marginal: p.marginal
        case .noGo: p.poor
        case .unavailable: p.tertiary
        }
    }
}

/// The verdict as a capsule: glyph, word and, when given, what limits it.
struct StatusBadge: View {
    let level: StatusLevel
    /// "incomplete data", "stale data"…
    var qualifier: String?
    var large = false
    @Environment(\.palette) private var palette

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the qualifier moves under the capsule instead of wrapping inside it.
        if typeSize.isAccessibilitySize, let qualifier {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                capsule(nil)
                Text(qualifier).font(.dsCallout).foregroundStyle(palette.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(level.word), \(qualifier)")
        } else {
            capsule(qualifier)
        }
    }

    private func capsule(_ qualifier: String?) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color(palette))
            Text(level.word)
                .foregroundStyle(palette.isField ? palette.primary : level.color(palette))
            if let qualifier {
                Text(qualifier)
                    .font(large ? .dsCallout : .dsFootnote)
                    .foregroundStyle(palette.secondary)
            }
        }
        .lineLimit(1)
        .font(large ? .title2.weight(.semibold) : .dsCallout.weight(.semibold))
        .padding(.horizontal, large ? DS.Space.m : DS.Space.s + 2)
        .padding(.vertical, large ? DS.Space.s : DS.Space.xs)
        .background(fill, in: Capsule())
        .overlay {
            if level == .unavailable {
                Capsule().strokeBorder(palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([level.word, qualifier].compactMap { $0 }.joined(separator: ", "))
    }

    private var fill: Color {
        if palette.isField { return palette.raised }
        return level == .unavailable ? .clear : level.color(palette).opacity(0.14)
    }
}

// MARK: - Values

/// "unavailable", never a zero, with an optional reason.
struct UnavailableValue: View {
    var reason: String?
    var font: Font = .dsBody
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Label {
                Text(Voice.unavailable).font(font)
            } icon: {
                Image(systemName: "circle.dashed").imageScale(.small)
            }
            .foregroundStyle(palette.secondary)
            if let reason {
                Text(reason).font(.dsFootnote).foregroundStyle(palette.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A labelled value with its unit and provenance. A nil value renders as unavailable.
struct MetricTile: View {
    let label: String
    let value: String?
    var unit: String?
    var detail: String?
    var source: SourceInfo?
    var now: Date = .now
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(label).eyebrow(palette)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Text(value).font(.dsMetric).foregroundStyle(palette.primary)
                    if let unit { Text(unit).font(.dsMetricUnit).foregroundStyle(palette.secondary) }
                }
            } else {
                UnavailableValue(font: .dsMetric)
            }
            if let detail {
                Text(detail).font(.dsFootnote).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source { ProvenanceChip(info: source, now: now) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A spec-sheet row: icon, label and a value underneath.
struct FactRow: View {
    let icon: String
    let label: String
    let value: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Image(systemName: icon)
                .foregroundStyle(palette.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(label).font(.dsFootnote.weight(.semibold)).foregroundStyle(palette.secondary)
                Text(value).font(.dsBody).foregroundStyle(palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One line of status about the data behind a screen.
struct DataStatusLine: View {
    let symbol: String
    let text: String
    var tone = StatusTone.neutral
    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tone == .caution ? palette.marginal : palette.secondary)
        }
        .font(.dsFootnote)
        .foregroundStyle(palette.secondary)
    }
}

// MARK: - Empty and explanatory

/// What an empty screen says, and the one thing to do about it.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var actionID: String?
    var action: (() -> Void)?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(palette.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.dsCallout)
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(ActionButtonStyle(.primary))
                    .accessibilityIdentifier(actionID ?? "")
                    .padding(.top, DS.Space.s)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Secondary detail behind a tap: methods, sources, long caveats.
struct MoreInfo<Content: View>: View {
    let title: String
    var id: String?
    @ViewBuilder var content: Content
    @State private var expanded = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Text(title)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .font(.dsFootnote.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(minHeight: DS.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressDimStyle())
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            .accessibilityIdentifier(id ?? "")
            if expanded {
                VStack(alignment: .leading, spacing: DS.Space.s) { content }
                    .font(.dsFootnote)
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
