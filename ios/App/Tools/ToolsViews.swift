import SwiftUI

/// A labelled number input; stacks vertically at accessibility text sizes.
struct FieldRow: View {
    let label: String
    let unit: String?
    @Binding var text: String
    var placeholder = ""
    var allowsNegative = false
    let id: String
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Text(label).foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                NumberField(label: label, text: $text, placeholder: placeholder, allowsNegative: allowsNegative, identifier: id)
                    .frame(minWidth: 80, maxWidth: typeSize.isAccessibilitySize ? .infinity : 140)
                if let unit {
                    Text(unit).foregroundStyle(palette.secondary).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ResultRow: View {
    let label: String
    let value: String
    var note: String?
    var id: String?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(palette.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(palette.primary)
            if let note {
                Text(note).font(.caption).foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id ?? "")
    }
}

struct ErrorLine: View {
    let message: String
    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            Text(message).foregroundStyle(palette.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(palette.marginal)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tools.error")
    }
}

/// A row of mutually exclusive choices drawn from the palette (system
/// segmented controls and menus are white in field mode).
struct ChoiceRow<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    let id: String
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                ForEach(options, id: \.0) { value, title in
                    let on = value == selection
                    Button { selection = value } label: {
                        Text(title)
                            .font(.subheadline.weight(on ? .bold : .regular))
                            .foregroundStyle(on ? palette.accent : palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(palette.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? palette.accent : palette.surface, lineWidth: 1.5))
                    }
                    .buttonStyle(PressDimStyle())
                    .accessibilityLabel("\(label): \(title)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(id).\(title)")
                }
            }
        }
    }
}
