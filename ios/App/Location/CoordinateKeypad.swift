import SwiftUI

/// Field mode's stand-in for the system keyboard, which cannot be drawn red:
/// digits, sign, point, separator and delete, all in palette colors.
struct CoordinateKeypad: View {
    @Binding var text: String

    private let rows: [[String]] = [
        ["7", "8", "9", "⌫"],
        ["4", "5", "6", "-"],
        ["1", "2", "3", ","],
        ["0", ".", " ", "clear"],
    ]

    var body: some View {
        Grid(horizontalSpacing: KeypadMetrics.spacing, verticalSpacing: KeypadMetrics.spacing) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            if key == "⌫" { Image(systemName: "delete.left") } else { Text(title(key)) }
                        }
                        .buttonStyle(KeypadKeyStyle(emphasized: key == "clear"))
                        .accessibilityLabel(spoken(key))
                    }
                }
            }
        }
        .accessibilityIdentifier("location.keypad")
    }

    private func title(_ key: String) -> String {
        switch key {
        case " ": "space"
        case "clear": "clear"
        default: key
        }
    }

    private func spoken(_ key: String) -> String {
        switch key {
        case "⌫": "Delete"
        case "-": "Minus"
        case ",": "Comma"
        case ".": "Point"
        case " ": "Space"
        case "clear": "Clear"
        default: key
        }
    }

    private func press(_ key: String) {
        switch key {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case "clear": text = ""
        default: text.append(key)
        }
    }
}
