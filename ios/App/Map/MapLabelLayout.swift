import CoreGraphics

/// Where the map's line labels go. Labels are views, so MapLibre can't place
/// them around each other: this picks, in priority order, the first spot
/// along each label's line where it overlaps nothing already placed and no
/// reserved rect (pin, puck, badge, buttons, scale bar), and lies wholly in
/// the visible map. A label with no such spot is hidden; the sheet still
/// lists every line. Pure geometry in map-view points, so it is unit-tested.
enum MapLabelLayout {
    struct Request: Equatable {
        let key: String
        /// Lower is placed first.
        let priority: Int
        let size: CGSize
        /// The line on screen, pin first.
        let start: CGPoint
        let end: CGPoint
        /// Fractions of the line to try, in order. At a stop the label's far
        /// edge sits on that point of the line, so 1 puts it at the line's end.
        let stops: [Double]
    }

    /// Event labels start at the line's end; the target and the at-time
    /// labels start part way out, clear of the pin.
    static let endStops: [Double] = [1, 0.85, 0.7]
    static let midStops: [Double] = [0.62, 0.8, 1, 0.48]

    /// The centre of every label shown. Keys that are absent are hidden.
    static func layout(_ requests: [Request], reserved: [CGRect], visible: CGRect, gap: CGFloat = 3) -> [String: CGPoint] {
        var taken = reserved
        var out: [String: CGPoint] = [:]
        let ordered = requests.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }
        for (_, r) in ordered {
            for stop in r.stops {
                let c = center(r, stop: stop)
                let rect = frame(center: c, size: r.size)
                guard visible.contains(rect) else { continue }
                let padded = rect.insetBy(dx: -gap, dy: -gap)
                guard !taken.contains(where: { $0.intersects(padded) }) else { continue }
                taken.append(rect)
                out[r.key] = c
                break
            }
        }
        return out
    }

    static func frame(center c: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
    }

    /// The label's centre when its far edge (along the line) is at `stop` of
    /// the line. Never closer to the pin than its own half-extent.
    static func center(_ r: Request, stop: Double) -> CGPoint {
        let dx = r.end.x - r.start.x, dy = r.end.y - r.start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else { return r.end }
        let ux = dx / length, uy = dy / length
        let reach = min(abs(ux) > 1e-6 ? r.size.width / 2 / abs(ux) : .infinity,
                        abs(uy) > 1e-6 ? r.size.height / 2 / abs(uy) : .infinity)
        let along = max(reach, CGFloat(stop) * length - reach)
        return CGPoint(x: r.start.x + ux * along, y: r.start.y + uy * along)
    }
}
