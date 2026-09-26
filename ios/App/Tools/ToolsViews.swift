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

