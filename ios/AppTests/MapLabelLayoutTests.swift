import CoreGraphics
import Foundation
import Testing
@testable import DarkSky

/// The map's label declutter (review B-6 c): labels never overlap each other
/// or a reserved rect, stay inside the visible map, and event labels sit at
/// their line's end.
struct MapLabelLayoutTests {
    /// iPhone 17 map with the sheet collapsed: 402 × 874, nav bar to 106, sheet from 690.
    let visible = CGRect(x: 4, y: 110, width: 394, height: 576)
    let pin = CGPoint(x: 201, y: 398)
    /// A two-line caption label ("Sun set 19:17" over "269°") at the default size.
    let labelSize = CGSize(width: 84, height: 30)

    func line(_ bearing: Double, length: Double = 169) -> CGPoint {
        let r = bearing * .pi / 180
        return CGPoint(x: pin.x + length * sin(r), y: pin.y - length * cos(r))
    }

    /// Candlestick Camp at z8, 27 Sep: sun rise 99° / transit 180° / set 263°,
    /// moon 101° / 183° / 262°, GC 132° / 178° / 226°, at-time lines, and the target.
    var candlestick: [MapLabelLayout.Request] {
        var out: [MapLabelLayout.Request] = [
            .init(key: "target", priority: 0, size: labelSize, start: pin, end: line(208), stops: MapLabelLayout.midStops),
        ]
        for (i, b) in [236.0, 118, 300].enumerated() {
            out.append(.init(key: "now\(i)", priority: 1, size: labelSize, start: pin, end: line(b), stops: MapLabelLayout.midStops))
        }
        for (i, b) in [99.0, 180, 263, 101, 183, 262, 132, 178, 226].enumerated() {
            out.append(.init(key: "event\(i)", priority: 2, size: labelSize, start: pin, end: line(b), stops: MapLabelLayout.endStops))
        }
        return out
    }

    var reserved: [CGRect] {
        [
            CGRect(x: pin.x - 15, y: pin.y - 15, width: 30, height: 30),   // pin
            CGRect(x: 330, y: 420, width: 72, height: 266),                // map buttons
            CGRect(x: 8, y: 114, width: 190, height: 28),                  // IR badge
            CGRect(x: 8, y: 640, width: 200, height: 40),                  // credit and scale bar
        ]
    }

    @Test("Thirteen labels at z8: none overlap each other or a reserved rect; all inside the map")
    func noOverlaps() {
        let placed = MapLabelLayout.layout(candlestick, reserved: reserved, visible: visible)
        let rects = placed.map { MapLabelLayout.frame(center: $0.value, size: labelSize) }
        for (i, a) in rects.enumerated() {
            #expect(visible.contains(a))
            for r in reserved { #expect(!a.intersects(r), "label \(a) covers reserved \(r)") }
            for b in rects[(i + 1)...] { #expect(!a.intersects(b), "\(a) overlaps \(b)") }
        }
        // The target always shows, and most lines keep a label.
        #expect(placed["target"] != nil)
        // Rise lines for the Sun (99°) and Moon (101°) nearly coincide: one of each such pair must go.
        #expect(placed.count >= 6, "only \(placed.count) of 13 labels placed")
        // Something has to give with 13 labels around one pin: those are hidden, not stacked.
        #expect(placed.count < candlestick.count)
    }

    @Test("An event label's far edge sits on its line's end")
    func eventLabelAtLineEnd() {
        let end = line(90)
        let r = MapLabelLayout.Request(key: "e", priority: 2, size: labelSize, start: pin, end: end, stops: [1])
        let c = MapLabelLayout.center(r, stop: 1)
        #expect(abs((c.x + labelSize.width / 2) - end.x) < 0.001)
        #expect(abs(c.y - end.y) < 0.001)
        let north = MapLabelLayout.center(.init(key: "n", priority: 2, size: labelSize, start: pin, end: line(0), stops: [1]), stop: 1)
        #expect(abs((north.y - labelSize.height / 2) - line(0).y) < 0.001)
    }

    @Test("A label that would cover a reserved rect moves along its line, or hides")
    func reservedRectsWin() {
        let end = line(90)
        let r = MapLabelLayout.Request(key: "e", priority: 2, size: labelSize, start: pin, end: end, stops: MapLabelLayout.endStops)
        let button = CGRect(x: end.x - 10, y: end.y - 10, width: 20, height: 20)
        let moved = MapLabelLayout.layout([r], reserved: [button], visible: visible)
        #expect(moved["e"] != nil)
        #expect(moved["e"] != MapLabelLayout.center(r, stop: 1))
        let hidden = MapLabelLayout.layout([r], reserved: [visible], visible: visible)
        #expect(hidden["e"] == nil)
    }

    @Test("Priority decides who keeps a contested spot; off-screen labels hide")
    func priorityAndBounds() {
        let a = MapLabelLayout.Request(key: "low", priority: 2, size: labelSize, start: pin, end: line(90), stops: [1])
        let b = MapLabelLayout.Request(key: "high", priority: 0, size: labelSize, start: pin, end: line(91), stops: [1])
        let placed = MapLabelLayout.layout([a, b], reserved: [], visible: visible)
        #expect(placed["high"] != nil)
        #expect(placed["low"] == nil)
        let far = MapLabelLayout.Request(key: "far", priority: 0, size: labelSize, start: pin, end: line(90, length: 400), stops: [1])
        #expect(MapLabelLayout.layout([far], reserved: [], visible: visible)["far"] == nil)
    }
}
