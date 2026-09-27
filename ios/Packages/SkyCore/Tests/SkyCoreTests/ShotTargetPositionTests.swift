import Foundation
import Testing
@testable import SkyCore

/// The map draws the shot target's line from `ShotTarget.position`: it must
/// be the same point the shot window judges.
@Suite("Shot target position")
struct ShotTargetPositionTests {
    let observer = try! Observer(latitude: 38.374031, longitude: -109.965416)
    let date = Date(timeIntervalSince1970: 1_790_568_000) // 2026-09-28 04:00 UTC

    @Test("The core is the planner's GC position")
    func core() throws {
        let p = try ShotTarget.galacticCore.position(observer, at: date)
        let gc = Planner.gcPosition(observer, at: date)
        #expect(p == gc)
    }

    @Test("A planet is its refracted apparent position")
    func planet() throws {
        let p = try ShotTarget.planet(.saturn).position(observer, at: date)
        let s = try SkyPositions.position(of: .saturn, at: date, observer: observer, refraction: .normal)
        #expect(abs(p.azimuthDeg - s.azimuthDeg) < 1e-9)
        #expect(abs(p.altitudeDeg - s.altitudeDeg) < 1e-9)
    }

    @Test("The Moon is its top limb: a quarter degree above its centre, same azimuth")
    func moon() throws {
        let p = try ShotTarget.moon.position(observer, at: date)
        let c = try SkyPositions.position(of: .moon, at: date, observer: observer, refraction: .normal)
        #expect(abs(p.azimuthDeg - c.azimuthDeg) < 0.05)
        #expect(p.altitudeDeg > c.altitudeDeg && p.altitudeDeg - c.altitudeDeg < 0.4)
    }
}
