import CoreLocation
import MapLibre
import SkyCore
import SwiftData
import SwiftUI

/// Buttons drawn on the map, bottom-trailing so a right thumb reaches them:
/// basemap, "plan at my location", centre on the pin and centre on me (follow
/// → follow with heading → off). Centring moves the camera only; "plan at my
/// location" is the one that changes the planning place (product review §4).
/// Everything but following the puck is also in the sheet (invariant 5).
struct MapOverlayControls: View {
    var controller: MapController
    var hasPin: Bool
    var centerOnPin: () -> Void
    var planHere: (CLLocationCoordinate2D) -> Void
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @State private var choosing = false
    /// On the map, field mode keeps the buttons at the map's brightness cap too.
    private var ink: Color { state.fieldMode ? palette.accent.opacity(Double(MapColors.fieldCap)) : palette.accent }

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.s) {
            if let notice = controller.notice {
                Text(notice)
                    .font(.dsFootnote).foregroundStyle(palette.primary)
                    .padding(DS.Space.s)
                    .floatingSurface(palette, shape: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .frame(maxWidth: 240, alignment: .trailing)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .accessibilityIdentifier("map.notice")
            }
            HStack(spacing: 6) {
                if choosing {
                    ForEach(Basemap.allCases) { b in
                        let on = controller.basemap(field: state.fieldMode) == b
                        Button {
                            controller.setBasemap(b, field: state.fieldMode)
                            choosing = false
                        } label: {
                            Text(b.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(on ? palette.background : ink)
                                .padding(.horizontal, 10).frame(height: 44)
                                .background(on ? ink : palette.background.opacity(0.9), in: Capsule())
                                .overlay(Capsule().stroke(ink.opacity(0.7), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .accessibilityIdentifier("map.basemap.\(b.rawValue)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                roundButton("square.3.layers.3d", label: "Basemap", value: controller.basemap(field: state.fieldMode).title, id: "map.basemapButton") {
                    choosing.toggle()
                }
            }
            roundButton("mappin.and.ellipse", label: "Plan at my location", id: "map.pinMe") {
                if let c = controller.userFix?.coordinate { planHere(c) }
            }
            .disabled(controller.userFix == nil)
            .opacity(controller.userFix == nil ? 0.45 : 1)
            roundButton("scope", label: "Center on pin", id: "map.centerPin", action: centerOnPin)
                .disabled(!hasPin)
                .opacity(hasPin ? 1 : 0.45)
            roundButton(trackingIcon, label: "Center on me", value: trackingValue, id: "map.locate") {
                controller.cycleTracking(fieldMode: state.fieldMode)
            }
        }
    }

    private var trackingIcon: String {
        switch controller.tracking {
        case .none: "location"
        case .follow: "location.fill"
        case .followWithHeading: "location.north.line.fill"
        }
    }

    private var trackingValue: String {
        switch controller.tracking {
        case .none: "Not following"
        case .follow: "Following"
        case .followWithHeading: "Following with heading"
        }
    }

    private func roundButton(_ icon: String, label: String, value: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 48, height: 48)
                .background(palette.background.opacity(0.9), in: Circle())
                .overlay(Circle().stroke(ink.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(id)
    }
}

/// The basemap's credit, on the map (every source asks for one), plus hidden
/// readouts the UI tests and the owner's timing check use.
struct MapAttributionOverlay: View {
    var controller: MapController
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        let b = controller.basemap(field: state.fieldMode)
        Text(Self.short(b))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(palette.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
            .allowsHitTesting(false)
            .accessibilityIdentifier("map.attribution")
            .background {
                Color.clear
                    .accessibilityElement()
                    .accessibilityIdentifier("map.userLocation")
                    .accessibilityLabel(userLabel)
                Color.clear
                    .accessibilityElement()
                    .accessibilityIdentifier("map.center")
                    .accessibilityLabel(centerLabel)
            }
    }

    static func short(_ b: Basemap) -> String {
        switch b {
        case .topo: "USGS The National Map"
        case .imagery: "USGS The National Map: imagery"
        case .darkRelief: "USGS TNM · terrain Mapzen/AWS, USGS"
        }
    }

    private var userLabel: String {
        guard let f = controller.userFix else {
            return "no fix (authorization \(controller.authorization.rawValue), puck \(controller.map?.showsUserLocation == true ? "on" : "off"))"
        }
        return String(format: "%@ %.5f,%.5f ±%.0f m", f.onScreen ? "puck on screen" : "puck off screen",
                      f.coordinate.latitude, f.coordinate.longitude, f.horizontalAccuracy)
    }

    private var centerLabel: String {
        guard let c = controller.camera else { return "unknown" }
        return String(format: "%.5f,%.5f z%.1f", c.center.latitude, c.center.longitude, c.zoom)
    }
}

/// Basemap choice in the panel, so it never needs the map (invariant 5).
struct BasemapSection: View {
    var data: MapData
    var controller: MapController
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        let chosen = controller.basemap(field: state.fieldMode)
        SectionCard("Basemap") {
            HStack(spacing: 6) {
                ForEach(Basemap.allCases) { b in
                    let on = b == chosen
                    Button { controller.setBasemap(b, field: state.fieldMode) } label: {
                        Text(b.title)
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(on ? palette.background : palette.accent)
                            .background(on ? palette.accent : palette.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.accent.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("basemap.\(b.rawValue)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(data.basemapDetail(chosen))
                .font(.caption2).foregroundStyle(palette.secondary)
                .accessibilityIdentifier("basemap.detail")
            Text(state.fieldMode ? "Field mode remembers its own basemap." : "Field mode keeps its own choice (Dark relief unless changed).")
                .font(.caption2).foregroundStyle(palette.secondary)
        }
    }
}

/// "Keep this area offline" for the current view and each saved spot, with
/// the size estimated before anything downloads, then progress.
struct OfflineAreasSection: View {
    var controller: MapController
    @Environment(\.palette) private var palette
    @Query(sort: \Spot.createdAt) private var spots: [Spot]
    @State private var offline = OfflineAreas()
    @State private var includeImagery = false
    @State private var message: String?

    var body: some View {
        SectionCard("Offline basemap") {
            Text("Keeps Topo and Dark relief tiles (they share them) plus terrain for an area; Imagery is optional and about doubles the size.")
                .font(.caption2).foregroundStyle(palette.secondary)
            Toggle(isOn: $includeImagery) {
                Text("Include imagery").font(.callout).foregroundStyle(palette.primary)
            }
            .toggleStyle(PaletteToggleStyle())
            .accessibilityIdentifier("offline.includeImagery")

            if let cam = controller.camera {
                let zooms = OfflineArea.viewZooms(currentZoom: cam.zoom)
                let bounds = cam.bounds.padded(by: OfflineArea.viewPadding)
                let e = offline.estimate(bounds: bounds, zooms: zooms, includeImagery: includeImagery)
                row(title: "This view", detail: "About \(size(e.bytes)), \(e.tiles) tiles, zoom \(zooms.lowerBound)–\(zooms.upperBound)",
                    id: "offline.view.estimate") {
                    PaletteButton("Keep", systemImage: "arrow.down.circle", label: "Keep this area offline") {
                        message = offline.add(
                            name: String(format: "View %.3f, %.3f", cam.center.latitude, cam.center.longitude), kind: "view",
                            bounds: bounds, zooms: zooms, includeImagery: includeImagery)
                    }
                    .accessibilityIdentifier("offline.keepView")
                }
            }
            ForEach(spots) { spot in
                let key = OfflineAreas.spotKey(latitude: spot.latitude, longitude: spot.longitude)
                if offline.area(forSpot: key) == nil {
                    let bounds = GeoBounds.around(latitude: spot.latitude, longitude: spot.longitude, radiusMeters: OfflineArea.spotRadiusMeters)
                    let e = offline.estimate(bounds: bounds, zooms: OfflineArea.spotZooms, includeImagery: includeImagery)
                    row(title: spot.name, detail: "10 × 10 km, about \(size(e.bytes))", id: "offline.spot.\(spot.name)") {
                        PaletteButton(systemImage: "arrow.down.circle", label: "Keep \(spot.name) offline") {
                            message = offline.add(name: spot.name, kind: "spot", spotKey: key, bounds: bounds,
                                                  zooms: OfflineArea.spotZooms, includeImagery: includeImagery)
                        }
                    }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(palette.marginal).accessibilityIdentifier("offline.message")
            }
            ForEach(offline.areas) { a in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.context.name + (a.context.includeImagery ? " + imagery" : ""))
                                .font(.callout).foregroundStyle(palette.primary)
                            Text(a.status + " (estimated \(size(a.context.estimateBytes)))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(a.isComplete ? palette.secondary : palette.marginal)
                                .accessibilityIdentifier("offline.area.status")
                        }
                        Spacer()
                        PaletteButton(systemImage: "trash", label: "Delete \(a.context.name)") { offline.remove(a) }
                            .accessibilityIdentifier("offline.delete")
                    }
                    if !a.isComplete {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.background)
                                Capsule().fill(palette.accent).frame(width: g.size.width * a.fraction)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .onAppear { offline.resumeAll() }
    }

    private func size(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    private func row(title: String, detail: String, id: String, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).foregroundStyle(palette.primary)
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier(id)
            }
            Spacer()
            action()
        }
    }
}
