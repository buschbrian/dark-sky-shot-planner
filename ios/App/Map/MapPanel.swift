import SkyCore
import SwiftUI

/// Text answers the map gives from its layers. Only layers whose data-status
/// says `real` may answer (ADR-0007, product review §3): a sample fixture or
/// an unconfirmed origin gives no answer at all, never a plausible one.
enum MapAnswers {
    /// The land manager under the pin, or nil when the layer may not answer.
    static func landManager(origin: PagesOrigin, keysAtPin: [String]?) -> String? {
        guard origin.mayAnswer else { return nil }
        guard let keys = keysAtPin else { return "Land manager: move the map so the pin is in view to read it." }
        if keys.isEmpty { return "Land manager: no PAD-US boundary here (private or undetermined)." }
        let labels = Array(Set(keys.map { ManagerTaxonomy.bundled.label(for: $0) })).sorted()
        return "Managed by \(labels.joined(separator: ", ")) (PAD-US). Check the manager's rules for camping and night access."
    }

    /// A tapped PAD-US polygon: nothing unless the layer is real.
    static func tappedLand(origin: PagesOrigin, key: String?) -> String? {
        guard origin.mayAnswer else { return nil }
        return "Managed by \(ManagerTaxonomy.bundled.label(for: key)) (PAD-US). Check the manager's rules for camping and night access."
    }
}

/// The sheet's content, below the peek.
extension MapScreen {
    @ViewBuilder var panel: some View {
        VStack(spacing: DS.Space.cardGap) {
            linesSection
            placeSection
            if !inspection.isEmpty { tappedSection }
            BasemapSection(data: data, controller: controller)
            layersSection
            offlineSection
            OfflineAreasSection(controller: controller)
        }
    }

    // MARK: Lines and time

    private var linesSection: some View {
        SectionCard("Shot line") {
            if let plan {
                NightScrubber(window: plan.window, darkness: darkness, moonFree: moonFree,
                              timeZone: state.place?.timeZone ?? .current, time: $time)
                if let t = targetLine {
                    HStack(spacing: DS.Space.s) {
                        LineSwatch(object: t.body, emphasized: true, below: t.position.altitudeDeg < 0)
                        Text(t.label).font(.dsCallout.weight(.semibold).monospacedDigit()).foregroundStyle(palette.primary)
                    }
                    Text("Target: \(t.name), from the shot plan. Change it on Tonight's shot window.")
                        .font(.dsFootnote).foregroundStyle(palette.secondary)
                }
                Toggle(isOn: $compare) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Compare").font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
                        Text("Sun, Moon and Galactic Center: rise, transit, set and now")
                            .font(.dsFootnote).foregroundStyle(palette.secondary)
                    }
                }
                .toggleStyle(PaletteToggleStyle())
                .accessibilityIdentifier("map.compare")
                let tz = state.place?.timeZone ?? .current
                let drawn = compareLines
                if !drawn.isEmpty {
                    ForEach(Array(drawn.enumerated()), id: \.offset) { _, f in
                        HStack(spacing: DS.Space.s) {
                            LineSwatch(object: CelestialBody(f.line.object), below: f.belowHorizon)
                            Text(MapPlanner.label(for: f.line, timeZone: tz))
                                .font(.dsFootnote.monospacedDigit())
                                .foregroundStyle(f.belowHorizon ? palette.secondary : palette.primary)
                        }
                    }
                }
                if !hiddenLabels.isEmpty {
                    Text("\(hiddenLabels.count) label\(hiddenLabels.count == 1 ? " is" : "s are") left off the map so none overlap; every line is listed here.")
                        .font(.dsFootnote).foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("map.hiddenLabels")
                }
                ProvenanceChip(info: SourceInfo(source: "astronomy-engine", note: "\(Voice.onDevice), refracted, flat horizon"))
                Color.clear.frame(height: 0)
                    .accessibilityElement()
                    .accessibilityIdentifier("map.lineSummary")
                    .accessibilityLabel(lineSummary)
            } else {
                Text("Set a place to draw the target's line, with the Sun, Moon and Galactic Center to compare.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
            }
        }
    }

    /// Every line drawn on the map, as text (VoiceOver and the UI tests).
    private var lineSummary: String {
        let tz = state.place?.timeZone ?? .current
        return ([targetLine?.label].compactMap { $0 } + compareLines.map { MapPlanner.label(for: $0.line, timeZone: tz) })
            .joined(separator: "; ")
    }

    private var compareLines: [MapLineFeature] {
        guard compare, let plan else { return [] }
        let tz = state.place?.timeZone ?? .current
        _ = tz
        let now = AzimuthLines.mapObjects.compactMap { object in
            plan.series[object].flatMap {
                AzimuthLines.line(object: object, series: $0, at: time, from: plan.pin.coordinate, lengthMeters: 1000)
            }
        }.map { MapPlanner.feature($0) }
        return now + eventFeatures
    }

    // MARK: Place

    private var placeSection: some View {
        SectionCard("Place") {
            if let place = state.place, let land = visible.contains(.land) ? MapAnswers.landManager(origin: data.origin(.land), keysAtPin: pinLand) : nil {
                _ = place
                Text(land).font(.dsFootnote).foregroundStyle(palette.primary)
                    .accessibilityIdentifier("map.landAtPin")
            }
            HStack(spacing: DS.Space.s) {
                TextField("", text: $coordText, prompt: Text("lat, lon  e.g. 38.3740, -109.9654").foregroundStyle(palette.secondary))
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.dsNumber)
                    .foregroundStyle(palette.primary)
                    .tint(palette.accent)
                    .padding(.horizontal, DS.Space.m)
                    .frame(minHeight: DS.minTarget)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .accessibilityIdentifier("map.coordinateField")
                    .focused($coordFocused)
                    .onSubmit(setTypedPlace)
                Button("Set", action: setTypedPlace)
                    .buttonStyle(ActionButtonStyle(.primary, compact: true))
                    .accessibilityLabel("Set place")
                    .accessibilityIdentifier("map.setPlace")
            }
            if let coordError {
                Text(coordError).font(.dsFootnote).foregroundStyle(palette.poor)
            }
            if !spots.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: DS.Space.s) {
                        ForEach(spots) { spot in
                            Button(spot.name) { state.choose(spot: spot) }
                                .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                                .accessibilityLabel("Use saved spot \(spot.name)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Text("Long-press the map to try a point; nothing changes until you tap Plan here.")
                .font(.dsFootnote).foregroundStyle(palette.secondary)
        }
    }

    private var tappedSection: some View {
        SectionCard("Tapped on the map") {
            ForEach(Array(inspection.enumerated()), id: \.offset) { _, item in
                Group {
                    switch item {
                    case let .place(name, designation, verified, _):
                        Text("\(name), \(designation)\(verified.map { " (verified \($0))" } ?? "")")
                    case let .land(key):
                        if let text = MapAnswers.tappedLand(origin: data.origin(.land), key: key) { Text(text) }
                    case let .smoke(density, satellite, start, end):
                        Text("Smoke, \(density ?? "density not given") (HMS, \(satellite ?? "?"), \(start.flatMap(HMSSmoke.time).map { MapData.utc($0, withDate: false) } ?? "?")–\(end.flatMap(HMSSmoke.time).map { MapData.utc($0, withDate: true) } ?? "?"))")
                    }
                }
                .font(.dsFootnote)
                .foregroundStyle(palette.primary)
            }
        }
    }

    // MARK: Layers: each row carries its own status and explanation

    private var layersSection: some View {
        SectionCard("Layers") {
            ForEach(MapLayer.allCases) { layer in
                let p = data.provenance(layer)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Toggle(isOn: binding(layer)) {
                        Text(layer.title).font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
                    }
                    .toggleStyle(PaletteToggleStyle())
                    .accessibilityIdentifier("layer.\(layer.rawValue)")
                    ProvenanceChip(info: SourceInfo(source: p.source, asOf: layerAsOf(layer), freshness: p.freshness,
                                                    note: layerStatus(layer, p)))
                    if layer == .smoke {
                        Text(data.smokeSummary())
                            .font(.dsFootnote).foregroundStyle(palette.primary)
                            .accessibilityIdentifier("layer.smoke.status")
                    }
                    if visible.contains(layer) { legend(layer) }
                    if layer == .infrared, visible.contains(.infrared), !data.irFrames.isEmpty {
                        HStack(spacing: DS.Space.s) {
                            Button { irPlaying.toggle() } label: {
                                Image(systemName: irPlaying ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                            .accessibilityLabel(irPlaying ? "Pause loop" : "Play loop")
                            Text("Frame \(MapData.utc(data.irFrames[irIndex % data.irFrames.count], withDate: true))")
                                .font(.dsData).foregroundStyle(palette.primary)
                        }
                    }
                    MoreInfo(title: "About this layer", id: "layer.\(layer.rawValue).about") {
                        Text("\(p.detail) License: \(p.license).")
                    }
                }
                if layer != MapLayer.allCases.last {
                    Rectangle().fill(palette.hairline).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder private func legend(_ layer: MapLayer) -> some View {
        switch layer {
        case .land:
            FlowSwatches(items: ManagerTaxonomy.bundled.entries.map { ($0.label, $0.color) }, field: state.fieldMode)
        case .lightPollution:
            FlowSwatches(items: RadianceLegend.bundled.map { ($0.label, $0.color) }, field: state.fieldMode)
        default:
            EmptyView()
        }
    }

    /// PMTiles archives are single AOI-wide files, so a whole copy on the phone
    /// covers every saved spot. MapLibre offline packs can't take them: its
    /// offline downloader rejects `pmtiles://` sources ("unsupported URL").
    private var offlineSection: some View {
        SectionCard("Offline") {
            Text("Published layers are kept on the phone and work at every saved spot without signal. Smoke and the IR loop are live; offline they show their \(Voice.lastGood) with its age.")
                .font(.dsFootnote).foregroundStyle(palette.secondary)
            ForEach([MapLayer.lightPollution, .land, .places]) { layer in
                let a = data.archive(layer)
                HStack {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(layer.title).font(.dsCallout).foregroundStyle(palette.primary)
                        Text(a.onPhone ? "On this phone\(a.bytes.map { ", " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")"
                            : "Not saved\(a.bytes.map { " (" + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + ")" } ?? "")")
                            .font(.dsData)
                            .foregroundStyle(a.onPhone ? palette.secondary : palette.marginal)
                            .accessibilityIdentifier("offline.\(layer.rawValue)")
                    }
                    Spacer()
                    if !a.onPhone {
                        Button { Task { await data.keepOffline(layer) } } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                        .accessibilityLabel("Keep \(layer.title) offline")
                    }
                }
            }
        }
    }

    /// What the chip counts the layer's age from (live layers only).
    private func layerAsOf(_ layer: MapLayer) -> Date? {
        switch layer {
        case .smoke: data.smokeAnalysis.end
        case .infrared: data.irFrames.last
        default: nil
        }
    }

    /// A short state in the one voice, or nil. Sample data is said once, in the peek.
    private func layerStatus(_ layer: MapLayer, _ p: LayerProvenance) -> String? {
        switch layer {
        case .lightPollution, .land, .places:
            return data.origin(layer) == .real && p.freshness == .unavailable ? Voice.unavailable : nil
        case .smoke:
            return nil
        case .infrared:
            return data.irFrames.isEmpty ? Voice.unavailable : nil
        }
    }
}

/// `radiance_mapping.breakpoints` from the bundled `config/app-config.json` (ADR-0005).
enum RadianceLegend {
    struct Entry: Decodable { let color: String; let label: String }
    private struct File: Decodable {
        struct Mapping: Decodable { let breakpoints: [Entry] }
        let radiance_mapping: Mapping
    }

    static let bundled: [Entry] = (try? JSONDecoder().decode(File.self, from: SharedResources.data("app-config.json")).radiance_mapping.breakpoints) ?? []
}

struct FlowSwatches: View {
    let items: [(String, String)]
    let field: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.0) { label, hex in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(palette.swatch(hex, field: field)).frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(palette.hairline, lineWidth: 0.5))
                    Text(label).font(.caption).foregroundStyle(palette.secondary)
                }
            }
        }
    }
}
