import SkyCore
import SwiftData
import SwiftUI

/// M10: exposure calculators driven by the owner's saved camera + lens.
struct ToolsScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context
    @Query(sort: \Gear.createdAt) private var gear: [Gear]
    @AppStorage("tools.selectedGear") private var selectedStamp = 0.0
    @State private var inputs = ToolsInputs()
    @State private var editing: EditTarget?

    enum EditTarget: Identifiable {
        case new
        case existing(Gear)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let g): "\(g.persistentModelID.hashValue)"
            }
        }
    }

    private var selected: Gear? {
        gear.first { $0.createdAt.timeIntervalSinceReferenceDate == selectedStamp } ?? gear.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                    gearSection
                    calculatorSection
                    CaptureToolsRow().padding(.top, 8)
                    NavigationLink(value: AboutRoute()) {
                        Disclosure {
                            Label("About and sync", systemImage: "info.circle")
                                .font(.dsCallout).foregroundStyle(palette.primary)
                        }
                        .frame(minHeight: DS.minTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressDimStyle())
                    .padding(.top, DS.Space.l)
                    .accessibilityIdentifier("tools.about")
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.Space.s)
                .padding(.bottom, DS.Space.xl)
            }
            .background(palette.background)
            .screenChrome("Tools")
            .navigationDestination(for: AboutRoute.self) { _ in AboutScreen() }
            .navigationDestination(for: Calculator.self) { calc in
                if let selected, let kit = try? GearKit(selected) {
                    CalculatorView(calculator: calc, kit: kit, inputs: inputs)
                }
            }
            .sheet(item: $editing) { target in
                GearEditor(gear: { if case .existing(let g) = target { g } else { nil } }()) { saved in
                    selectedStamp = saved.createdAt.timeIntervalSinceReferenceDate
                }
                .environment(\.palette, palette)
            }
        }
        #if DEBUG
        .onAppear(perform: resetForTests)
        #endif
    }

    private var editingAllowed: Bool { !state.fieldMode }

    @ViewBuilder private var gearSection: some View {
        Text("Camera and lens").eyebrow(palette).padding(.top, DS.Space.xs)
        if gear.isEmpty {
            SectionCard {
                Text("No gear yet").font(.dsHeadline).foregroundStyle(palette.primary)
                Text("Add your camera's sensor size and resolution and your lens's focal length and widest aperture, from the manual or spec sheet. The calculators use them.")
                    .font(.dsCallout).foregroundStyle(palette.secondary)
            }
        }
        ForEach(gear) { item in gearRow(item) }
        if editingAllowed {
            Button { editing = .new } label: {
                Label("Add camera and lens", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(.secondary))
            .accessibilityIdentifier("tools.addGear")
        } else {
            DataStatusLine(symbol: "keyboard", text: "Adding and editing gear is off in field mode: the system keyboard can't be drawn red.")
        }
    }

    private func gearRow(_ item: Gear) -> some View {
        let isSelected = item.persistentModelID == selected?.persistentModelID
        let kit = try? GearKit(item)
        return HStack(alignment: .top, spacing: 12) {
            Button { selectedStamp = item.createdAt.timeIntervalSinceReferenceDate } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? palette.accent : palette.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(item.name).font(.dsHeadline).foregroundStyle(palette.primary)
                        if let kit {
                            Text(kit.lensSummary).font(.dsCallout).foregroundStyle(palette.primary)
                            Text(kit.cameraSummary).font(.dsData).foregroundStyle(palette.secondary)
                        } else {
                            Text("This profile could not be read. Edit or delete it.")
                                .font(.dsFootnote).foregroundStyle(palette.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(PressDimStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint("Uses this gear in the calculators")
            if editingAllowed {
                Button { editing = .existing(item) } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(ActionButtonStyle(.quiet))
                .accessibilityLabel("Edit \(item.name)")
            }
        }
        .padding(DS.Space.card)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .strokeBorder(isSelected && gear.count > 1 ? palette.accent : .clear, lineWidth: DS.Stroke.focus))
    }

    @ViewBuilder private var calculatorSection: some View {
        Text("Calculators").eyebrow(palette).padding(.top, DS.Space.m)
        if let selected, let kit = try? GearKit(selected) {
            Text("Using \(kit.name)").font(.dsFootnote).foregroundStyle(palette.secondary)
            ForEach(Calculator.allCases) { calc in
                NavigationLink(value: calc) {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: calc.symbol).foregroundStyle(palette.accent).frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(calc.title).font(.dsHeadline).foregroundStyle(palette.primary)
                            Text(calc.subtitle).font(.dsFootnote).foregroundStyle(palette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.forward").font(.dsFootnote.weight(.semibold))
                            .foregroundStyle(palette.tertiary).accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(DS.Space.card)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                }
                .buttonStyle(PressDimStyle())
                .accessibilityIdentifier("tools.calc.\(calc.rawValue)")
            }
        } else {
            // Not an error: the calculators need a camera and lens to work from.
            DataStatusLine(symbol: "camera.aperture",
                           text: gear.isEmpty ? "The calculators appear here once a camera and lens are saved."
                                              : "Pick a camera and lens above to use the calculators.")
        }
    }

    #if DEBUG
    /// `DS_RESET_GEAR=1` starts UI tests from an empty gear list.
    private func resetForTests() {
        guard ProcessInfo.processInfo.environment["DS_RESET_GEAR"] == "1", !Self.didReset else { return }
        Self.didReset = true
        try? context.delete(model: Gear.self)
        try? context.save()
        selectedStamp = 0
    }

    private static var didReset = false
    #endif
}
