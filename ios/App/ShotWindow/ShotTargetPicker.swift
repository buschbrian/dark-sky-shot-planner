import SkyCore
import SwiftUI

/// Pick what the shot points at and how high it must be. Every control is
/// drawn by the app from the palette (no system menus or pickers), so field
/// mode stays pure red.
struct ShotTargetPicker: View {
    @Binding var plan: ShotPlan
    @Environment(\.palette) private var palette

    struct Group: Identifiable {
        let id: String
        let title: String
        let targets: [ShotTarget]
    }

    static let groups: [Group] = [
        Group(id: "mw", title: "Milky Way", targets: [
            .galacticCore, .milkyWayArch(.coreToCygnus), .milkyWayArch(.cygnusToCassiopeia),
        ]),
        Group(id: "solar", title: "Moon and planets", targets: [.moon] + SkyObject.planets.map(ShotTarget.planet)),
        Group(id: "fixed", title: "Stars and deep sky", targets: FixedTarget.catalog.map(ShotTarget.fixed)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ForEach(Self.groups) { group in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(group.title)
                        .eyebrow(palette)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s) {
                            ForEach(group.targets, id: \.id) { target in
                                chip(target)
                            }
                        }
                    }
                }
            }
            minimumAltitude
        }
    }

    private func chip(_ target: ShotTarget) -> some View {
        let selected = plan.target == target
        return Button {
            plan.target = target
        } label: {
            Text(Self.label(target))
                .font(.dsCallout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.onAccent : palette.primary)
                .padding(.horizontal, DS.Space.m)
                .frame(minHeight: DS.minTarget)
                .background(Capsule().fill(selected ? palette.accentFill : palette.raised))
                .overlay(Capsule().strokeBorder(selected ? palette.accentEdge : palette.hairline,
                                                lineWidth: selected ? DS.Stroke.focus : DS.Stroke.hairline))
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(target.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("shot.target.\(target.id)")
    }

    private var minimumAltitude: some View {
        HStack(spacing: DS.Space.s) {
            Text(plan.minAltitudeDeg == 0 ? "Just clear the skyline" : "At least \(Int(plan.minAltitudeDeg))° up")
                .font(.dsCallout)
                .foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            step("minus", by: -1)
            step("plus", by: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minimum altitude")
        .accessibilityValue(plan.minAltitudeDeg == 0 ? "the skyline" : "\(Int(plan.minAltitudeDeg)) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(1)
            case .decrement: move(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("shot.minAltitude")
    }

    private func step(_ symbol: String, by delta: Int) -> some View {
        Button { move(delta) } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
        .accessibilityHidden(true)
    }

    private func move(_ delta: Int) {
        let choices = ShotPlan.minAltitudeChoices
        let i = choices.firstIndex(of: plan.minAltitudeDeg) ?? 0
        plan.minAltitudeDeg = choices[min(max(i + delta, 0), choices.count - 1)]
    }

    static func label(_ target: ShotTarget) -> String {
        switch target {
        case .galacticCore: "Core"
        case .milkyWayArch(let s): "Arch: \(s.name)"
        case .fixed(let f): f.name
        default: target.name
        }
    }
}
