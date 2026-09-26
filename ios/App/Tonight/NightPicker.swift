import SkyCore
import SwiftUI

/// Previous / next night, a calendar, and a way back to tonight. Drawn from
/// the palette only: the system date picker cannot be made red.
struct NightPicker: View {
    let night: NightDate
    let tonight: NightDate
    let choose: (NightDate) -> Void
    let openCalendar: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                step("chevron.left", "Previous night", "tonight.previousNight", -1)
                Button(action: openCalendar) {
                    VStack(spacing: 2) {
                        Text("Night of \(Format.nightTitle(night))")
                            .font(.headline)
                            .foregroundStyle(palette.primary)
                        Text(relative)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Night of \(Format.nightSpoken(night)), \(relative)")
                .accessibilityHint("Opens a calendar")
                .accessibilityIdentifier("tonight.date")
                step("chevron.right", "Next night", "tonight.nextNight", 1)
            }
            if night != tonight {
                Button("Back to tonight") { choose(tonight) }
                    .buttonStyle(PaletteButtonStyle(palette: palette))
                    .accessibilityIdentifier("tonight.backToTonight")
            }
        }
    }

    private var relative: String {
        let days = daysBetween(tonight, night)
        switch days {
        case 0: return "tonight"
        case 1: return "tomorrow night"
        case -1: return "last night"
        case let d where d > 0: return "in \(d) nights"
        default: return "\(-days) nights ago"
        }
    }

    private func step(_ icon: String, _ label: String, _ id: String, _ days: Int) -> some View {
        Button { choose(night.adding(days: days)) } label: {
            Image(systemName: icon).frame(width: 44, height: 44)
        }
        .buttonStyle(PaletteButtonStyle(palette: palette))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

func daysBetween(_ a: NightDate, _ b: NightDate) -> Int {
    Calendar(identifier: .gregorian).dateComponents([.day], from: Format.noon(a), to: Format.noon(b)).day ?? 0
}

/// A month grid of nights, in palette colors.
struct NightCalendar: View {
    let selected: NightDate
    let tonight: NightDate
    let choose: (NightDate) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @State private var month: (year: Int, month: Int) = (2026, 1)

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .gmt
        return c
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    monthStep("chevron.left", "Previous month", -1)
                    Spacer()
                    Text(monthTitle)
                        .font(.title3.bold())
                        .foregroundStyle(palette.primary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    monthStep("chevron.right", "Next month", 1)
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.caption).foregroundStyle(palette.secondary).accessibilityHidden(true)
                    }
                    ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 40) }
                    ForEach(days, id: \.self) { day in
                        dayButton(day)
                    }
                }
                Button("Tonight") {
                    choose(tonight)
                    dismiss()
                }
                .buttonStyle(PaletteButtonStyle(palette: palette))
                Spacer()
            }
            .padding()
            .background(palette.background)
            .navigationTitle("Choose a night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Choose a night").font(.headline).foregroundStyle(palette.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(palette.accent)
                }
                .sharedBackgroundVisibility(state.fieldMode ? .hidden : .automatic)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.background)
        .presentationDragIndicator(.hidden)
        .fieldSafe(state.fieldMode)
        .onAppear { month = (selected.year, selected.month) }
    }

    private var monthTitle: String {
        Format.noon(NightDate(year: month.year, month: month.month, day: 1)!)
            .formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let s = Self.utc.veryShortWeekdaySymbols
        let shift = Self.utc.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    private var first: NightDate { NightDate(year: month.year, month: month.month, day: 1)! }

    private var leadingBlanks: Int {
        let weekday = Self.utc.component(.weekday, from: Format.noon(first))
        return (weekday - Self.utc.firstWeekday + 7) % 7
    }

    private var days: [NightDate] {
        (0..<31).compactMap { NightDate(year: month.year, month: month.month, day: $0 + 1) }
    }

    private func dayButton(_ day: NightDate) -> some View {
        let isSelected = day == selected
        let isTonight = day == tonight
        return Button {
            choose(day)
            dismiss()
        } label: {
            Text("\(day.day)")
                .font(.body.monospacedDigit().weight(isTonight ? .bold : .regular))
                .foregroundStyle(isSelected ? palette.onAccent : palette.primary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    Circle().fill(isSelected ? palette.accent : .clear)
                        .overlay(Circle().stroke(isTonight ? palette.accent : .clear, lineWidth: 1.5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.nightSpoken(day) + (isTonight ? ", tonight" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func monthStep(_ icon: String, _ label: String, _ delta: Int) -> some View {
        Button {
            let shifted = NightDate(year: month.year, month: month.month, day: 1)!
            let date = Self.utc.date(byAdding: .month, value: delta, to: Format.noon(shifted))!
            let c = Self.utc.dateComponents([.year, .month], from: date)
            month = (c.year!, c.month!)
        } label: {
            Image(systemName: icon).frame(width: 44, height: 44)
        }
        .buttonStyle(PaletteButtonStyle(palette: palette))
        .accessibilityLabel(label)
    }
}
