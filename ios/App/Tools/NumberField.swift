import SwiftUI
import UIKit

/// A number entry field with an in-app keypad drawn from the palette. The
/// system keyboard cannot be tinted, so in field mode it would light the
/// screen white; this keypad never does.
struct NumberField: UIViewRepresentable {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var allowsNegative = false
    var identifier: String
    @Environment(\.palette) private var palette

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = .right
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.accessibilityLabel = label
        field.accessibilityIdentifier = identifier
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let pad = NumberKeypad(allowsNegative: allowsNegative)
        pad.field = field
        pad.onChange = { [weak coordinator = context.coordinator, weak field] in
            if let field { coordinator?.changed(field) }
        }
        field.inputView = pad
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
        field.textColor = UIColor(palette.primary)
        field.tintColor = UIColor(palette.accent)
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: UIColor(palette.secondary)])
        (field.inputView as? NumberKeypad)?.apply(palette)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: max(44, uiView.intrinsicContentSize.height))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        @objc func changed(_ field: UITextField) {
            let value = field.text ?? ""
            if text.wrappedValue != value { text.wrappedValue = value }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}

final class NumberKeypad: UIView {
    weak var field: UITextField?
    var onChange: (() -> Void)?

    private enum Key: Hashable {
        case digit(String), point, delete, sign, done

        var title: String {
            switch self {
            case .digit(let d): d
            case .point: "."
            case .delete: "⌫"
            case .sign: "+/−"
            case .done: "Done"
            }
        }

        var id: String {
            switch self {
            case .digit(let d): d
            case .point: "point"
            case .delete: "delete"
            case .sign: "sign"
            case .done: "done"
            }
        }

        var spoken: String {
            switch self {
            case .digit(let d): d
            case .point: "decimal point"
            case .delete: "delete"
            case .sign: "change sign"
            case .done: "done"
            }
        }
    }

    private var buttons: [(Key, UIButton)] = []
    private var palette = Palette.standard

    init(allowsNegative: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        autoresizingMask = [.flexibleWidth]
        let rows: [[Key]] = [
            [.digit("1"), .digit("2"), .digit("3")],
            [.digit("4"), .digit("5"), .digit("6")],
            [.digit("7"), .digit("8"), .digit("9")],
            [.point, .digit("0"), .delete],
            allowsNegative ? [.sign, .done] : [.done],
        ]
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 6
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        for row in rows {
            let line = UIStackView()
            line.axis = .horizontal
            line.spacing = 6
            line.distribution = .fillEqually
            for key in row {
                let button = UIButton(configuration: .plain())
                button.accessibilityLabel = key.spoken
                button.accessibilityIdentifier = "keypad.\(key.id)"
                button.accessibilityTraits = .keyboardKey
                button.addAction(UIAction { [weak self] _ in self?.press(key) }, for: .touchUpInside)
                buttons.append((key, button))
                line.addArrangedSubview(button)
            }
            grid.addArrangedSubview(line)
        }
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            grid.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            grid.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        apply(.standard)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ palette: Palette) {
        guard buttons.isEmpty == false else { return }
        self.palette = palette
        backgroundColor = UIColor(palette.background)
        let font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 22, weight: .medium), maximumPointSize: 30)
        for (key, button) in buttons {
            var config = UIButton.Configuration.plain()
            var title = AttributedString(key.title)
            title.font = key == .done ? font.withWeight(.semibold) : font
            config.attributedTitle = title
            config.baseForegroundColor = UIColor(key == .done ? palette.accent : palette.primary)
            config.background.backgroundColor = UIColor(palette.surface)
            config.background.cornerRadius = 8
            button.configuration = config
        }
    }

    private func press(_ key: Key) {
        guard let field else { return }
        let text = field.text ?? ""
        switch key {
        case .digit(let d): field.insertText(d)
        case .point: if !text.contains(".") { field.insertText(".") }
        case .delete: field.deleteBackward()
        case .sign:
            field.text = text.hasPrefix("-") ? String(text.dropFirst()) : "-" + text
            field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        case .done: field.resignFirstResponder()
        }
        onChange?()
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        .systemFont(ofSize: pointSize, weight: weight)
    }
}
