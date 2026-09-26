import SwiftUI

/// The app's buttons, drawn from the palette so field mode has no system
/// white fill or blue label. Content buttons stay solid; Liquid Glass is kept
/// for the floating layer (toolbars, the tab bar, map overlays).
struct ActionButtonStyle: ButtonStyle {
    enum Kind {
        /// The one main action in a view: accent fill.
        case primary
        /// Everything else: raised fill with a hairline.
        case secondary
        /// Text only, in the accent color.
        case quiet
    }

    let kind: Kind
    var compact = false
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    init(_ kind: Kind = .secondary, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsCallout.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 0 : (compact ? DS.Space.m : DS.Space.l))
            .frame(minWidth: DS.minTarget, minHeight: DS.minTarget)
            .background {
                switch kind {
                case .primary:
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(palette.accent)
                case .secondary:
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(palette.raised)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(palette.hairline, lineWidth: DS.Stroke.hairline))
                case .quiet:
                    Color.clear
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.45))
    }

    private var foreground: Color {
        switch kind {
        case .primary: palette.onAccent
        case .secondary: palette.primary
        case .quiet: palette.accent
        }
    }
}

/// Dims on press instead of the system grey highlight.
struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The one switch: a palette track and knob (the system switch has a white
/// knob and a grey track). Reads the palette from the environment.
struct PaletteToggleStyle: ToggleStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    init() {}

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .center, spacing: DS.Space.m) {
                configuration.label
                    .foregroundStyle(palette.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(configuration.isOn ? palette.accent : palette.raised)
                    .overlay(Capsule().strokeBorder(configuration.isOn ? .clear : palette.hairline, lineWidth: 1))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? palette.onAccent : palette.secondary)
                            .padding(3)
                    }
                    .frame(width: 50, height: 30)
                    .animation(.snappy(duration: 0.15), value: configuration.isOn)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A key on the in-app keypads (coordinates, numbers): the system keyboard
/// cannot be drawn red, so field mode types with these.
struct KeypadKeyStyle: ButtonStyle {
    var emphasized = false
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(emphasized ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(emphasized ? palette.accent : palette.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? palette.hairline : palette.raised,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// UIKit mirror of `KeypadKeyStyle` for `NumberKeypad`.
enum KeypadMetrics {
    static let spacing: CGFloat = 6
    static let cornerRadius = DS.Radius.control
}

/// A row of mutually exclusive choices drawn from the palette (the system
/// segmented control and menus are white in field mode).
struct ChoiceRow<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    let id: String
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(label).font(.dsCallout).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DS.Space.xs)) : AnyLayout(HStackLayout(spacing: DS.Space.xs))
            layout {
                ForEach(options, id: \.0) { value, title in
                    let on = value == selection
                    Button { selection = value } label: {
                        Text(title)
                            .font(.dsCallout.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? palette.onAccent : palette.primary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? palette.accent : palette.raised,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.control - 2, style: .continuous))
                    }
                    .buttonStyle(PressDimStyle())
                    .accessibilityLabel("\(label): \(title)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(id).\(title)")
                }
            }
            .padding(DS.Space.xxs)
            .background(palette.background, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
    }
}

/// A determinate bar without the system's grey track.
struct PaletteProgress: View {
    @Environment(\.palette) private var palette
    let value: Double

    var body: some View {
        Capsule().fill(palette.raised)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(palette.accent).frame(width: g.size.width * min(max(value, 0), 1)) }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Row content plus a chevron in the palette (the List chevron is grey).
struct Disclosure<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            content
            Spacer(minLength: DS.Space.s)
            Image(systemName: "chevron.forward")
                .font(.dsFootnote.weight(.semibold))
                .foregroundStyle(palette.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
