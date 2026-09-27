import MapLibre
import UIKit

/// The owner's location, drawn entirely from the palette: MapLibre's default
/// puck has a fixed white rim, which field mode's red multiply turns into a
/// full-brightness red ring. A dot, a heading wedge and an accuracy halo.
final class UserPuckView: MLNUserLocationAnnotationView {
    var colors: MapColors? { didSet { if colors != oldValue { restyle() } } }

    private let halo = CAShapeLayer()
    private let wedge = CAShapeLayer()
    private let dot = CAShapeLayer()
    static let size: CGFloat = 26

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        for l in [halo, wedge, dot] { layer.addSublayer(l) }
        let r = Self.size / 2
        dot.path = UIBezierPath(ovalIn: CGRect(x: r - 8, y: r - 8, width: 16, height: 16)).cgPath
        dot.lineWidth = 3
        // A fan pointing up (north before rotation), 22 pt long.
        let fan = UIBezierPath()
        fan.move(to: CGPoint(x: r, y: r))
        fan.addArc(withCenter: CGPoint(x: r, y: r), radius: 24, startAngle: -.pi / 2 - 0.45, endAngle: -.pi / 2 + 0.45, clockwise: true)
        fan.close()
        wedge.path = fan.cgPath
        wedge.frame = bounds
        halo.frame = bounds
        isAccessibilityElement = true
        accessibilityLabel = "Your location"
        accessibilityIdentifier = "map.userPuck"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func restyle() {
        guard let c = colors else { return }
        dot.fillColor = c.accent.cgColor
        dot.strokeColor = c.background.cgColor
        wedge.fillColor = c.accent.withAlphaComponent(0.45).cgColor
        halo.fillColor = c.accent.withAlphaComponent(0.12).cgColor
        halo.strokeColor = c.accent.withAlphaComponent(0.5).cgColor
        halo.lineWidth = 1
    }

    override func update() {
        guard let map = mapView, let loc = userLocation?.location else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = Self.size / 2
        let accuracyPts = loc.horizontalAccuracy / max(0.01, map.metersPerPoint(atLatitude: loc.coordinate.latitude))
        let h = min(120, max(0, accuracyPts))
        halo.path = h > r ? UIBezierPath(ovalIn: CGRect(x: r - h, y: r - h, width: 2 * h, height: 2 * h)).cgPath : nil
        if let heading = userLocation?.heading, heading.headingAccuracy >= 0 {
            let deg = (heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading) - map.direction
            wedge.isHidden = false
            wedge.setAffineTransform(CGAffineTransform(rotationAngle: deg * .pi / 180))
        } else {
            wedge.isHidden = true
        }
        CATransaction.commit()
    }
}
