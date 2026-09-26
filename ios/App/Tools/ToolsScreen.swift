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
                VStack(alignment: .leading, spacing: 12) {
                    gearSection
                    calculatorSection
                    CaptureToolsRow().padding(.top, 8)
                }
                .padding()
            }
            .background(palette.background)
            .paletteChrome("Tools")
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
        Text("Camera and lens").font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
        if gear.isEmpty {
            Card {
                Text("No gear yet").font(.headline).foregroundStyle(palette.primary)
                Text("Add your camera's sensor size and resolution and your lens's focal length and widest aperture, from the manual or spec sheet. The calculators use them.")
                    .font(.subheadline).foregroundStyle(palette.secondary)
            }
        }
        ForEach(gear) { item in gearRow(item) }
        if editingAllowed {
            Button { editing = .new } label: {
                Label("Add camera and lens", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressDimStyle())
            .accessibilityIdentifier("tools.addGear")
        } else {
            Text("Adding and editing gear is off in field mode: the system keyboard cannot be dimmed red.")
                .font(.footnote).foregroundStyle(palette.secondary)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.headline).foregroundStyle(palette.primary)
                        if let kit {
                            Text(kit.lensSummary).font(.subheadline).foregroundStyle(palette.primary)
                            Text(kit.cameraSummary).font(.caption).foregroundStyle(palette.secondary)
                        } else {
                            Text("This profile could not be read. Edit or delete it.")
                                .font(.caption).foregroundStyle(palette.secondary)
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
                    Image(systemName: "pencil").foregroundStyle(palette.accent).padding(4)
                }
                .buttonStyle(PressDimStyle())
                .accessibilityLabel("Edit \(item.name)")
            }
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var calculatorSection: some View {
        Text("Calculators").font(.headline).foregroundStyle(palette.primary)
            .accessibilityAddTraits(.isHeader).padding(.top, 8)
        if let selected, let kit = try? GearKit(selected) {
            Text("Using \(kit.name)").font(.footnote).foregroundStyle(palette.secondary)
            ForEach(Calculator.allCases) { calc in
                NavigationLink(value: calc) {
                    HStack(spacing: 12) {
                        Image(systemName: calc.symbol).foregroundStyle(palette.accent).frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calc.title).font(.headline).foregroundStyle(palette.primary)
                            Text(calc.subtitle).font(.caption).foregroundStyle(palette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").foregroundStyle(palette.secondary).accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(14)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressDimStyle())
                .accessibilityIdentifier("tools.calc.\(calc.rawValue)")
            }
        } else {
            Text("Add or pick a camera and lens to use the calculators.")
                .font(.subheadline).foregroundStyle(palette.secondary)
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
