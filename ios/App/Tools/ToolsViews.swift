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
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.xs))
            : AnyLayout(HStackLayout(spacing: DS.Space.s))
        layout {
            Text(label).font(.dsCallout).foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: DS.Space.xs) {
                NumberField(label: label, text: $text, placeholder: placeholder, allowsNegative: allowsNegative, identifier: id)
                    .frame(minWidth: 80, maxWidth: typeSize.isAccessibilitySize ? .infinity : 140)
                if let unit {
                    Text(unit).font(.dsCallout).foregroundStyle(palette.secondary).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.Space.m)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
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
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(label).font(.dsFootnote.weight(.semibold)).foregroundStyle(palette.secondary)
            Text(value).font(.title2.weight(.medium).monospacedDigit()).foregroundStyle(palette.primary)
            if let note {
                Text(note).font(.dsFootnote).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

