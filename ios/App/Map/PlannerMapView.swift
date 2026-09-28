import CoreLocation
import MapLibre
import SkyCore
import SwiftUI

/// What the map should show; the coordinator diffs it against what it last applied.
struct MapSnapshot: Equatable {
    var styleURL: URL?
    var colors: MapColors
    var pin: GeoCoordinate?
    /// A long-pressed point awaiting "Plan here" (review B-9).
    var candidate: GeoCoordinate?
    /// Rise/transit/set (Compare view): rebuilt only when the pin, night or zoom changes.
    var eventLines: [MapLineFeature]
    /// The scrubber's Sun/Moon/GC lines (Compare view).
    var atTimeLines: [MapLineFeature]
    /// The shot plan's target at the scrubber's time: the map's main line.
    var target: MapTargetLine?
    var labels: [MapLabel]
    var visible: Set<MapLayer>
    var smoke: Data?
    var irFrames: [Date]
    var irIndex: Int
    /// The bar above and the resting sheet below: the camera centres between them.
    var insets: UIEdgeInsets
    /// Window-coordinate frames of what floats over the map (badge, buttons, banners).
    var obstructions: [CGRect]
}

struct MapTargetLine: Equatable {
    let name: String
    let body: CelestialBody
    let position: HorizontalPosition
    /// Pin first.
    let coordinates: [GeoCoordinate]
    let label: String
}

/// One line label: the line on the ground and how eager it is to be shown.
struct MapLabel: Equatable {
    let key: String
    let text: String
    let body: CelestialBody
    let priority: Int
    let start: GeoCoordinate
    let end: GeoCoordinate
    let emphasized: Bool
    let stops: [Double]

    init(key: String, text: String, body: CelestialBody, priority: Int, start: GeoCoordinate, end: GeoCoordinate,
         emphasized: Bool, stops: [Double]) {
        self.key = key
        self.text = text
        self.body = body
        self.priority = priority
        self.start = start
        self.end = end
        self.emphasized = emphasized
        self.stops = stops
    }

    init(_ f: MapLineFeature, text: String, priority: Int, stops: [Double]) {
        self.init(key: "\(f.line.object.rawValue).\(f.line.event.rawValue)", text: text, body: CelestialBody(f.line.object),
                  priority: priority, start: f.coordinates[0], end: f.coordinates[f.coordinates.count - 1],
                  emphasized: false, stops: stops)
    }
}

/// Tab-appear to first map frame, for the owner's speed check.
enum MapTiming {
    nonisolated(unsafe) static var tabAppeared: CFTimeInterval?
}

/// Something the owner tapped on the map. The map adds detail; it is never
/// the only way to set a place or a layer (invariant 5).
enum MapInspection: Equatable {
    case place(name: String, designation: String, verifiedOn: String?, sourceURL: String?)
    case land(managerKey: String?)
    case smoke(density: String?, satellite: String?, start: String?, end: String?)
}

struct PlannerMapView: UIViewRepresentable {
    var snapshot: MapSnapshot
    /// Basemap choice, camera and location, shared with the controls outside the map.
    var controller: MapController
    /// A long-press: a candidate point, never a place change by itself.
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onCamera: (_ zoom: Double, _ shortSidePoints: Double) -> Void
    var onInspect: ([MapInspection]) -> Void
    /// PAD-US manager keys under the pin, from the rendered tiles; nil when the pin is off screen.
    var onPinLand: ([String]?) -> Void
    var onTiming: (String) -> Void = { _ in }
    /// Line labels left off the map so none overlap (keys), and the window
    /// frames of those shown (the UI tests' overlap check).
    var onLabels: (_ hidden: [String], _ shown: [CGRect]) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: snapshot.styleURL)
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "map.view"
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.showsScale = true
        map.prefetchesTiles = true
        map.tileCacheEnabled = true
        map.compassViewPosition = .topRight
        map.scaleBarPosition = .bottomLeft
        map.automaticallyAdjustsContentInset = false
        map.backgroundColor = snapshot.colors.background
        map.tintColor = snapshot.colors.accent
        // The puck shows without asking only when location is already allowed;
        // the "center on me" button asks (never in field mode).
        map.showsUserLocation = controller.locationAllowed
        if let (center, zoom) = MapController.launchCamera {
            map.setCenter(center, zoomLevel: zoom, animated: false)
        } else if let pin = snapshot.pin {
            map.setCenter(CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude), zoomLevel: 9, animated: false)
        } else {
            map.setCenter(CLLocationCoordinate2D(latitude: 39.5, longitude: -111.5), zoomLevel: 5, animated: false)
        }
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        map.addGestureRecognizer(press)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        for g in map.gestureRecognizers ?? [] where g is UITapGestureRecognizer { tap.require(toFail: g) }
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        context.coordinator.lastPin = snapshot.pin
        controller.map = map
        controller.onBasemapChange = { [weak coordinator = context.coordinator] in coordinator?.applyBasemap() }
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(snapshot)
    }

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        map.delegate = nil
    }

    final class Coordinator: NSObject {
        var parent: PlannerMapView
        weak var map: MLNMapView?
        var lastPin: GeoCoordinate?
        private var droppedPin: GeoCoordinate?
        private var applied: MapSnapshot?
        private var styleReady = false
        private var labelAnnotations: [LabelAnnotation] = []
        private var pinAnnotation: PinAnnotation?
        private var candidateAnnotation: CandidateAnnotation?
        private var reported: ([String], [CGRect])?
        private var irTimes: [Date] = []
        private var firstFrameMs: Int?
        private var fullRenderMs: Int?

        init(_ parent: PlannerMapView) { self.parent = parent }

        func apply(_ s: MapSnapshot) {
            guard let map else { return }
            if map.styleURL != s.styleURL, let url = s.styleURL {
                styleReady = false
                map.styleURL = url
            }
            map.backgroundColor = s.colors.background
            // The scale bar draws white; under field mode's red multiply that is full red.
            map.scaleBar.alpha = s.colors.field ? MapColors.fieldCap * 0.9 : 1
            if map.tintColor != s.colors.accent {
                map.tintColor = s.colors.accent
                if let u = map.userLocation { (map.view(for: u) as? UserPuckView)?.colors = s.colors }
            }
            if map.contentInset != s.insets {
                map.setContentInset(s.insets, animated: applied != nil, completionHandler: nil)
            }
            // MapLibre adds the view's safe area to the content inset for its
            // ornaments, counting it twice here: keep the scale bar just above
            // the credit and the compass under the bar.
            let scale = CGPoint(x: 8, y: 40 - map.safeAreaInsets.bottom)
            if map.scaleBarMargins != scale { map.scaleBarMargins = scale }
            let compass = CGPoint(x: 8, y: 8 - map.safeAreaInsets.top)
            if map.compassViewMargins != compass { map.compassViewMargins = compass }
            if s.pin != lastPin {
                if let pin = s.pin, pin != droppedPin {
                    let c = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                    map.setCenter(c, zoomLevel: max(map.zoomLevel, 8), animated: true)
                }
                lastPin = s.pin
            }
            updateAnnotations(s, on: map)
            DispatchQueue.main.async { [weak self] in self?.declutter() }
            guard styleReady, let style = map.style else { return }
            let old = applied
            applied = s
            let force = old == nil
            if force || old?.eventLines != s.eventLines {
                (style.source(withIdentifier: "planner-events") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: s.eventLines.map(polyline))
            }
            if force || old?.atTimeLines != s.atTimeLines {
                (style.source(withIdentifier: "planner-now") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: s.atTimeLines.map(polyline))
            }
            if force || old?.target != s.target || old?.colors != s.colors {
                applyTarget(s, style: style)
            }
            if force || old?.smoke != s.smoke {
                (style.source(withIdentifier: "smoke") as? MLNShapeSource)?.shape = s.smoke.flatMap {
                    try? MLNShape(data: $0, encoding: String.Encoding.utf8.rawValue)
                }
            }
            if irTimes != s.irFrames { syncInfrared(style, s) }
            if force || old?.colors.field != s.colors.field { applyBasemap() }
            if force || old?.visible != s.visible {
                for layer in MapLayer.allCases {
                    for id in MapStyle.layerIds[layer] ?? [] { style.layer(withIdentifier: id)?.isVisible = s.visible.contains(layer) }
                }
            }
            if force || old?.visible != s.visible || old?.irIndex != s.irIndex || old?.irFrames != s.irFrames {
                let current = irTimes.isEmpty ? nil : irTimes[s.irIndex % irTimes.count]
                for t in irTimes {
                    guard let l = style.layer(withIdentifier: Self.irId(t)) as? MLNRasterStyleLayer else { continue }
                    l.isVisible = s.visible.contains(.infrared)
                    l.rasterOpacity = NSExpression(forConstantValue: t == current ? 0.7 : 0)
                }
            }
        }

        /// Shows the chosen basemap's layers and hides the others; tiles of a
        /// hidden basemap are never requested.
        func applyBasemap() {
            guard styleReady, let style = map?.style else { return }
            let chosen = parent.controller.basemap(field: parent.snapshot.colors.field)
            for (b, ids) in MapStyle.basemapLayerIds {
                for id in ids { style.layer(withIdentifier: id)?.isVisible = b == chosen }
            }
            // Topo and Dark relief share a source: show the chosen one's layers last.
            for id in MapStyle.basemapLayerIds[chosen] ?? [] { style.layer(withIdentifier: id)?.isVisible = true }
        }

        // MARK: Runtime layers

        fileprivate func styleDidLoad(_ style: MLNStyle) {
            let s = parent.snapshot
            let colors = s.colors
            let beneathPlaces = style.layer(withIdentifier: "places-circle")
            func insert(_ layer: MLNStyleLayer) {
                if let beneathPlaces { style.insertLayer(layer, below: beneathPlaces) } else { style.addLayer(layer) }
            }

            let smoke = MLNShapeSource(identifier: "smoke", shape: nil, options: nil)
            style.addSource(smoke)
            let fill = MLNFillStyleLayer(identifier: "smoke-fill", source: smoke)
            fill.fillColor = NSExpression(forConstantValue: colors.marginal)
            fill.fillOpacity = NSExpression(mglJSONObject: [
                "match", ["get", "Density"], "Heavy", 0.45, "Medium", 0.3, 0.15,
            ])
            insert(fill)
            let edge = MLNLineStyleLayer(identifier: "smoke-line", source: smoke)
            edge.lineColor = NSExpression(forConstantValue: colors.marginal)
            edge.lineWidth = NSExpression(forConstantValue: 1)
            edge.lineOpacity = NSExpression(forConstantValue: 0.7)
            insert(edge)

            // Thin lines with a narrow halo, so roads and terrain still read
            // beneath them; the target's line is the one drawn heavier.
            for (id, width) in [("planner-events", 1.75), ("planner-now", 2.25)] {
                let source = MLNShapeSource(identifier: id, shape: nil, options: nil)
                style.addSource(source)
                let halo = MLNLineStyleLayer(identifier: "\(id)-halo", source: source)
                halo.lineColor = NSExpression(forConstantValue: colors.background)
                halo.lineWidth = NSExpression(forConstantValue: width + 2)
                halo.lineOpacity = NSExpression(forConstantValue: 0.5)
                halo.lineCap = NSExpression(forConstantValue: "round")
                style.addLayer(halo)
                for object in AzimuthLines.mapObjects {
                    let body = CelestialBody(object)
                    let l = MLNLineStyleLayer(identifier: "\(id)-\(object.rawValue)", source: source)
                    l.predicate = NSPredicate(format: "object == %@", object.rawValue)
                    l.lineColor = NSExpression(forConstantValue: colors.line(for: body))
                    l.lineWidth = NSExpression(forConstantValue: width)
                    l.lineOpacity = NSExpression(mglJSONObject: ["case", ["==", ["get", "below"], true], 0.4, 0.9])
                    if let d = CelestialStyle.mapDash(body, width: width) { l.lineDashPattern = NSExpression(forConstantValue: d) }
                    style.addLayer(l)
                }
            }
            let target = MLNShapeSource(identifier: "planner-target", shape: nil, options: nil)
            style.addSource(target)
            let targetHalo = MLNLineStyleLayer(identifier: "planner-target-halo", source: target)
            targetHalo.lineColor = NSExpression(forConstantValue: colors.background)
            targetHalo.lineWidth = NSExpression(forConstantValue: Self.targetWidth + 2.5)
            targetHalo.lineOpacity = NSExpression(forConstantValue: 0.6)
            targetHalo.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(targetHalo)
            let targetLine = MLNLineStyleLayer(identifier: "planner-target-line", source: target)
            targetLine.lineWidth = NSExpression(forConstantValue: Self.targetWidth)
            targetLine.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(targetLine)
            irTimes = []
            styleReady = true
            applied = nil
            apply(s)
        }

        static func irId(_ t: Date) -> String { "ir-\(Int(t.timeIntervalSince1970))" }
        static let targetWidth = 3.5

        private func applyTarget(_ s: MapSnapshot, style: MLNStyle) {
            let source = style.source(withIdentifier: "planner-target") as? MLNShapeSource
            guard let t = s.target else { source?.shape = nil; return }
            var coords = t.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            source?.shape = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            if let l = style.layer(withIdentifier: "planner-target-line") as? MLNLineStyleLayer {
                l.lineColor = NSExpression(forConstantValue: s.colors.line(for: t.body))
                l.lineOpacity = NSExpression(forConstantValue: t.position.altitudeDeg < 0 ? 0.5 : 1)
                l.lineDashPattern = CelestialStyle.mapDash(t.body, width: Self.targetWidth).map { NSExpression(forConstantValue: $0) }
            }
        }

        /// Keeps one raster source per GIBS frame time: frames that aged out are
        /// removed, new ones added, the rest (and their loaded tiles) kept.
        private func syncInfrared(_ style: MLNStyle, _ s: MapSnapshot) {
            let keep = Set(s.irFrames)
            for t in irTimes where !keep.contains(t) {
                if let l = style.layer(withIdentifier: Self.irId(t)) { style.removeLayer(l) }
                if let src = style.source(withIdentifier: Self.irId(t)) { style.removeSource(src) }
            }
            let below = style.layer(withIdentifier: "smoke-fill")
            for t in s.irFrames where style.source(withIdentifier: Self.irId(t)) == nil {
                let src = MLNRasterTileSource(identifier: Self.irId(t), tileURLTemplates: [GIBSTimeDomain.tileURLTemplate(time: t)], options: [
                    .tileSize: 256, .minimumZoomLevel: 0, .maximumZoomLevel: GIBSTimeDomain.maxZoom,
                ])
                style.addSource(src)
                let l = MLNRasterStyleLayer(identifier: Self.irId(t), source: src)
                l.rasterFadeDuration = NSExpression(forConstantValue: 0)
                l.rasterOpacity = NSExpression(forConstantValue: 0)
                l.isVisible = s.visible.contains(.infrared)
                if let below { style.insertLayer(l, below: below) } else { style.addLayer(l) }
            }
            irTimes = s.irFrames
        }

        private func polyline(_ f: MapLineFeature) -> MLNPolylineFeature {
            var coords = f.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            let p = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            p.attributes = ["object": f.line.object.rawValue, "event": f.line.event.rawValue, "below": f.belowHorizon]
            return p
        }

        // MARK: Annotations (pin and line labels, drawn as views so no glyph server is needed)

        private func updateAnnotations(_ s: MapSnapshot, on map: MLNMapView) {
            if let pin = s.pin {
                let c = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                if let a = pinAnnotation { a.coordinate = c } else {
                    let a = PinAnnotation()
                    a.coordinate = c
                    pinAnnotation = a
                    map.addAnnotation(a)
                }
                (map.view(for: pinAnnotation!) as? PinView)?.configure(s.colors)
            } else if let a = pinAnnotation {
                map.removeAnnotation(a)
                pinAnnotation = nil
            }

            if let c = s.candidate {
                let coord = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
                if let a = candidateAnnotation { a.coordinate = coord } else {
                    let a = CandidateAnnotation()
                    a.coordinate = coord
                    candidateAnnotation = a
                    map.addAnnotation(a)
                }
                (map.view(for: candidateAnnotation!) as? CandidateView)?.configure(s.colors)
            } else if let a = candidateAnnotation {
                map.removeAnnotation(a)
                candidateAnnotation = nil
            }

            let keys = Set(s.labels.map(\.key))
            let stale = labelAnnotations.filter { !keys.contains($0.key) }
            if !stale.isEmpty { map.removeAnnotations(stale) }
            labelAnnotations.removeAll { !keys.contains($0.key) }
            for l in s.labels {
                let c = CLLocationCoordinate2D(latitude: l.end.latitude, longitude: l.end.longitude)
                if let a = labelAnnotations.first(where: { $0.key == l.key }) {
                    a.coordinate = c
                    a.title = l.text
                    a.label = l
                    (map.view(for: a) as? LabelView)?.configure(l, colors: s.colors)
                } else {
                    let a = LabelAnnotation()
                    a.key = l.key
                    a.label = l
                    a.coordinate = c
                    a.title = l.text
                    labelAnnotations.append(a)
                    map.addAnnotation(a)
                }
            }
        }

        /// Places line labels with `MapLabelLayout`: at their line's end (the
        /// target and at-time ones part way out), never over each other, the
        /// pin, the puck, the badge, the buttons, the banner or the scale bar.
        /// Labels that fit nowhere are hidden; the sheet lists every line.
        fileprivate func declutter(report: Bool = true) {
            guard let map else { return }
            let s = parent.snapshot
            var reserved = s.obstructions.map { map.convert($0, from: nil).insetBy(dx: -4, dy: -4) }
            for a in [pinAnnotation as MLNAnnotation?, candidateAnnotation, map.userLocation].compactMap({ $0 }) {
                if let v = map.view(for: a), v.superview != nil { reserved.append(v.convert(v.bounds, to: map).insetBy(dx: -4, dy: -4)) }
            }
            if !map.scaleBar.isHidden, map.scaleBar.alpha > 0 { reserved.append(map.scaleBar.frame) }
            if map.compassView.alpha > 0, !map.compassView.isHidden { reserved.append(map.compassView.frame) }
            let visible = map.bounds.inset(by: s.insets).insetBy(dx: 4, dy: 4)
            var views: [String: (LabelView, CGPoint)] = [:]
            var requests: [MapLabelLayout.Request] = []
            for a in labelAnnotations {
                guard let l = a.label, let v = map.view(for: a) as? LabelView else { continue }
                let anchor = map.convert(a.coordinate, toPointTo: map)
                views[l.key] = (v, anchor)
                requests.append(.init(
                    key: l.key, priority: l.priority, size: v.bounds.size,
                    start: map.convert(CLLocationCoordinate2D(latitude: l.start.latitude, longitude: l.start.longitude), toPointTo: map),
                    end: anchor, stops: l.stops))
            }
            let placed = MapLabelLayout.layout(requests, reserved: reserved, visible: visible)
            var shown: [CGRect] = []
            for (key, (v, anchor)) in views {
                if let c = placed[key] {
                    v.centerOffset = CGVector(dx: c.x - anchor.x, dy: c.y - anchor.y)
                    v.alpha = 1
                    v.isHidden = false
                    v.isAccessibilityElement = true
                    let size = v.bounds.size
                    shown.append(map.convert(MapLabelLayout.frame(center: c, size: size), to: nil).integral)
                } else {
                    v.alpha = 0
                    v.isHidden = true
                    v.isAccessibilityElement = false
                }
            }
            // Reported once the map settles, not on every frame of a pan.
            guard report else { return }
            let hidden = requests.map(\.key).filter { placed[$0] == nil }.sorted()
            shown.sort { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
            if reported?.0 != hidden || reported?.1 != shown {
                reported = (hidden, shown)
                DispatchQueue.main.async { [weak self] in self?.parent.onLabels(hidden, shown) }
            }
        }

        // MARK: Gestures

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map else { return }
            let c = map.convert(g.location(in: map), toCoordinateFrom: map)
            droppedPin = GeoCoordinate(latitude: c.latitude, longitude: c.longitude)
            parent.onLongPress(c)
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let map else { return }
            let p = g.location(in: map)
            let rect = CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)
            var found: [MapInspection] = []
            for f in map.visibleFeatures(in: rect, styleLayerIdentifiers: ["places-circle"]).prefix(1) {
                found.append(.place(
                    name: f.attribute(forKey: "name") as? String ?? "Unnamed place",
                    designation: f.attribute(forKey: "designation") as? String ?? "",
                    verifiedOn: f.attribute(forKey: "verified_on") as? String,
                    sourceURL: f.attribute(forKey: "source_url") as? String))
            }
            for f in map.visibleFeatures(at: p, styleLayerIdentifiers: ["land-fill"]).prefix(3) {
                found.append(.land(managerKey: f.attribute(forKey: "manager") as? String))
            }
            for f in map.visibleFeatures(at: p, styleLayerIdentifiers: ["smoke-fill"]).prefix(1) {
                found.append(.smoke(
                    density: f.attribute(forKey: "Density") as? String, satellite: f.attribute(forKey: "Satellite") as? String,
                    start: f.attribute(forKey: "Start") as? String, end: f.attribute(forKey: "End_") as? String))
            }
            parent.onInspect(found)
        }

        fileprivate func recordFrame(fullyRendered: Bool) {
            guard fullRenderMs == nil, let start = MapTiming.tabAppeared, let map else { return }
            let ms = Int((CACurrentMediaTime() - start) * 1000)
            if firstFrameMs == nil { firstFrameMs = ms }
            if fullyRendered && styleReady { fullRenderMs = ms }
            parent.onTiming("first frame \(firstFrameMs ?? -1) ms; fully rendered \(fullRenderMs.map(String.init) ?? "pending") ms")
        }

        fileprivate func reportCamera() {
            guard let map else { return }
            let seen = map.bounds.inset(by: map.contentInset)
            parent.onCamera(map.zoomLevel, Double(max(120, min(seen.width, seen.height))))
            let b = map.visibleCoordinateBounds
            parent.controller.report(camera: MapController.Camera(
                center: map.centerCoordinate, zoom: map.zoomLevel,
                bounds: GeoBounds(west: b.sw.longitude, south: b.sw.latitude, east: b.ne.longitude, north: b.ne.latitude)))
            reportUser()
        }

        fileprivate func reportUser() {
            guard let map else { return }
            guard map.showsUserLocation, let u = map.userLocation, let loc = u.location,
                  CLLocationCoordinate2DIsValid(loc.coordinate), loc.horizontalAccuracy >= 0 else {
                parent.controller.report(fix: nil)
                return
            }
            let pt = map.convert(loc.coordinate, toPointTo: map)
            let view = map.view(for: u)
            view?.accessibilityIdentifier = "map.userPuck"
            let heading = u.heading.flatMap { $0.headingAccuracy >= 0 ? $0.trueHeading : nil }
            parent.controller.report(fix: MapController.UserFix(
                coordinate: loc.coordinate, horizontalAccuracy: loc.horizontalAccuracy, heading: heading,
                onScreen: map.bounds.contains(pt) && view?.superview != nil && view?.isHidden == false))
        }

        fileprivate func reportPinLand() {
            guard let map, let pin = lastPin, styleReady else { return }
            let pt = map.convert(CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude), toPointTo: map)
            guard map.bounds.contains(pt) else { parent.onPinLand(nil); return }
            let keys = map.visibleFeatures(at: pt, styleLayerIdentifiers: ["land-fill"]).compactMap { $0.attribute(forKey: "manager") as? String }
            parent.onPinLand(keys)
        }
    }
}

extension PlannerMapView.Coordinator: @MainActor MLNMapViewDelegate {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        styleDidLoad(style)
        reportCamera()
    }

    @objc(mapView:didUpdateUserLocation:)
    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        reportUser()
    }

    @objc(mapView:didChangeUserTrackingMode:animated:)
    func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
        parent.controller.report(trackingMode: mode)
    }

    @objc(mapViewRegionIsChanging:)
    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
        declutter(report: false)
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        declutter()
        reportCamera()
        reportPinLand()
    }

    func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
        recordFrame(fullyRendered: fullyRendered)
    }

    func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
        if fullyRendered { reportPinLand() }
    }

    func mapView(_ mapView: MLNMapView, viewFor annotation: any MLNAnnotation) -> MLNAnnotationView? {
        let colors = parent.snapshot.colors
        if annotation is MLNUserLocation {
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "user") as? UserPuckView ?? UserPuckView(reuseIdentifier: "user")
            v.colors = colors
            return v
        }
        if annotation is PinAnnotation {
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? PinView ?? PinView(reuseIdentifier: "pin")
            v.configure(colors)
            return v
        }
        if annotation is CandidateAnnotation {
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "candidate") as? CandidateView ?? CandidateView(reuseIdentifier: "candidate")
            v.configure(colors)
            return v
        }
        if let a = annotation as? LabelAnnotation, let l = a.label {
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "label") as? LabelView ?? LabelView(reuseIdentifier: "label")
            v.configure(l, colors: colors)
            v.alpha = 0
            DispatchQueue.main.async { [weak self] in self?.declutter() }
            return v
        }
        return nil
    }

    func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: any MLNAnnotation) -> Bool { false }
}

nonisolated final class PinAnnotation: MLNPointAnnotation {}

nonisolated final class CandidateAnnotation: MLNPointAnnotation {}

nonisolated final class LabelAnnotation: MLNPointAnnotation {
    var key = ""
    nonisolated(unsafe) var label: MapLabel?
}

final class PinView: MLNAnnotationView {
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        layer.cornerRadius = 11
        layer.borderWidth = 3
        isAccessibilityElement = true
        accessibilityLabel = "Planner pin"
        accessibilityIdentifier = "map.pin"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ colors: MapColors) {
        backgroundColor = colors.background
        layer.borderColor = colors.accent.cgColor
    }
}

/// A long-pressed point waiting for "Plan here": a dashed ring, so it never
/// reads as the planning pin.
final class CandidateView: MLNAnnotationView {
    private let ring = CAShapeLayer()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        ring.lineWidth = 2.5
        ring.lineDashPattern = [4, 3]
        layer.addSublayer(ring)
        isAccessibilityElement = true
        accessibilityLabel = "Candidate point"
        accessibilityIdentifier = "map.candidatePin"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ colors: MapColors) {
        ring.strokeColor = colors.accent.cgColor
        ring.fillColor = colors.background.withAlphaComponent(0.35).cgColor
    }
}

final class LabelView: MLNAnnotationView {
    private let label = UILabel()
    /// Map labels cap at extra large (DESIGN rule 7); the sheet lists them at any size.
    static let maxCategory = UIContentSizeCategory.extraLarge

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        label.numberOfLines = 2
        label.textAlignment = .center
        addSubview(label)
        layer.cornerRadius = 6
        layer.borderWidth = 1.5
        isUserInteractionEnabled = false
        accessibilityIdentifier = "map.label"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static func font(emphasized: Bool, category: UIContentSizeCategory) -> UIFont {
        let capped = category > maxCategory ? maxCategory : category
        let traits = UITraitCollection(preferredContentSizeCategory: capped)
        let base = UIFont.preferredFont(forTextStyle: emphasized ? .subheadline : .caption1, compatibleWith: traits)
        return UIFont.monospacedDigitSystemFont(ofSize: base.pointSize, weight: emphasized ? .bold : .semibold)
    }

    func configure(_ l: MapLabel, colors: MapColors) {
        // "Sun set 19:17 · 269°" → two short lines.
        var parts = l.text.components(separatedBy: " · ")
        let head = parts.isEmpty ? l.text : parts.removeFirst()
        label.text = parts.isEmpty ? head : head + "\n" + parts.joined(separator: " · ")
        label.font = Self.font(emphasized: l.emphasized, category: traitCollection.preferredContentSizeCategory)
        label.textColor = colors.primary
        backgroundColor = colors.background.withAlphaComponent(0.82)
        layer.borderColor = colors.line(for: l.body).cgColor
        layer.borderWidth = l.emphasized ? 2 : 1
        label.sizeToFit()
        let size = CGSize(width: label.bounds.width + 10, height: label.bounds.height + 4)
        bounds.size = size
        label.frame = CGRect(x: 5, y: 2, width: label.bounds.width, height: label.bounds.height)
        accessibilityLabel = l.text
    }
}
