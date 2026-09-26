import Foundation
import Testing
@testable import SkyCore

private let r = Double.pi / 180
private func tand(_ deg: Double) -> Double { tan(deg * r) }
private func sind(_ deg: Double) -> Double { sin(deg * r) }
private func cosd(_ deg: Double) -> Double { cos(deg * r) }

/// Rows are device X, Y, Z written in Core Motion's reference frame
/// (X north, Y west, Z up), exactly as `CMAttitude.rotationMatrix` holds them.
private func attitude(_ x: SIMD3<Double>, _ y: SIMD3<Double>, _ z: SIMD3<Double>) -> DeviceAttitude {
    DeviceAttitude(coreMotionRotationMatrix: RotationMatrix(rows: x, y, z))
}

private let north = SIMD3<Double>(1, 0, 0), south = SIMD3<Double>(-1, 0, 0)
private let west = SIMD3<Double>(0, 1, 0), east = SIMD3<Double>(0, -1, 0)
private let up = SIMD3<Double>(0, 0, 1)

/// Portrait, held upright, back camera level and facing azimuth `az`.
private func levelFacing(_ az: Double) -> DeviceAttitude {
    DeviceAttitude(
        deviceX: HorizontalPosition(altitudeDeg: 0, azimuthDeg: az + 90),
        deviceY: HorizontalPosition(altitudeDeg: 90, azimuthDeg: 0),
        deviceZ: HorizontalPosition(altitudeDeg: 0, azimuthDeg: az + 180))
}

/// Portrait 3024 × 4032 (a 12 MP back camera), ~69° across the long side.
private let camera = CameraIntrinsics(fx: 2900, fy: 2900, cx: 1512, cy: 2016, width: 3024, height: 4032)

private func expectPixel(
    _ projection: SkyProjection, _ u: Double, _ v: Double, inFrame: Bool = true,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let p = projection.pixel else {
        Issue.record("expected a pixel, got \(projection)", sourceLocation: sourceLocation)
        return
    }
    #expect(abs(p.u - u) < 1e-6 && abs(p.v - v) < 1e-6, "\(p) vs (\(u), \(v))", sourceLocation: sourceLocation)
    #expect((projection == .inFrame(p)) == inFrame, sourceLocation: sourceLocation)
}

@Suite("Night AR projection (M7)")
struct SkyProjectionTests {
    @Test("identity attitude is Apple's yaw 0: flat, screen up, device X north, top edge west")
    func identityConvention() {
        let flat = SkyProjector(attitude: DeviceAttitude(coreMotionRotationMatrix: .identity), intrinsics: camera)
        // The back camera looks at the nadir, so the zenith is behind it.
        #expect(flat.project(HorizontalPosition(altitudeDeg: 90, azimuthDeg: 0)) == .behindCamera)
        #expect(flat.boresight.altitudeDeg < -89.999)
        // 10° from the nadir toward the west shows toward the top edge (device +Y).
        expectPixel(flat.project(HorizontalPosition(altitudeDeg: -80, azimuthDeg: 270)), 1512, 2016 - 2900 * tand(10))
        // ...and toward the north on the right edge (device +X).
        expectPixel(flat.project(HorizontalPosition(altitudeDeg: -80, azimuthDeg: 0)), 1512 + 2900 * tand(10), 2016)
    }

    @Test("level, facing north: the north horizon is the principal point")
    func levelNorth() {
        // Screen right is east, top is up, the screen faces south.
        let p = SkyProjector(attitude: attitude(east, up, south), intrinsics: camera)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 0)), 1512, 2016)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 5, azimuthDeg: 0)), 1512, 2016 - 2900 * tand(5))
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 10)), 1512 + 2900 * tand(10), 2016)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 350)), 1512 - 2900 * tand(10), 2016)
        #expect(maxDifference(p.attitude, levelFacing(0)) < 1e-15)
    }

    @Test("pitched up 30°: alt 30° is centred, the horizon drops below centre")
    func pitchedUp() {
        let p = SkyProjector(
            attitude: attitude(east, SIMD3(-sind(30), 0, cosd(30)), SIMD3(-cosd(30), 0, -sind(30))),
            intrinsics: camera)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 30, azimuthDeg: 0)), 1512, 2016)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 40, azimuthDeg: 0)), 1512, 2016 - 2900 * tand(10))
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 0)), 1512, 2016 + 2900 * tand(30))
        #expect(abs(p.boresight.altitudeDeg - 30) < 1e-9)
        #expect(azimuthDelta(p.boresight.azimuthDeg, 0) < 1e-9)
    }

    @Test("rolled 20° clockwise (top edge toward east): a point above centre moves up-left")
    func rolled() {
        let p = SkyProjector(
            attitude: attitude(SIMD3(0, -cosd(20), -sind(20)), SIMD3(0, -sind(20), cosd(20)), south),
            intrinsics: camera)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 0)), 1512, 2016)
        expectPixel(
            p.project(HorizontalPosition(altitudeDeg: 10, azimuthDeg: 0)),
            1512 - 2900 * sind(20) * tand(10), 2016 - 2900 * cosd(20) * tand(10))
    }

    @Test("level, facing east: screen right is south")
    func levelEast() {
        let p = SkyProjector(attitude: attitude(south, up, west), intrinsics: camera)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 90)), 1512, 2016)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 100)), 1512 + 2900 * tand(10), 2016)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 20, azimuthDeg: 90)), 1512, 2016 - 2900 * tand(20))
        #expect(maxDifference(p.attitude, levelFacing(90)) < 1e-15)
    }

    @Test("behind the camera and outside the frame")
    func behindAndOutside() throws {
        let p = SkyProjector(attitude: levelFacing(0), intrinsics: camera)
        #expect(p.project(HorizontalPosition(altitudeDeg: 10, azimuthDeg: 180)) == .behindCamera)
        #expect(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 90)) == .behindCamera)
        expectPixel(p.project(HorizontalPosition(altitudeDeg: 0, azimuthDeg: 60)), 1512 + 2900 * tand(60), 2016, inFrame: false)
        // Edge arrows: east is to the right, the zenith straight up, the point behind-right to the right.
        #expect(abs(try #require(p.screenDirection(toward: HorizontalPosition(altitudeDeg: 0, azimuthDeg: 60)))) < 1e-12)
        #expect(abs(try #require(p.screenDirection(toward: HorizontalPosition(altitudeDeg: 80, azimuthDeg: 0))) + .pi / 2) < 1e-12)
        #expect(abs(try #require(p.screenDirection(toward: HorizontalPosition(altitudeDeg: 0, azimuthDeg: 135)))) < 1e-12)
    }

    @Test("unprojection round-trips pixels and sky directions")
    func roundTrip() throws {
        // An arbitrary attitude: facing 147°, then pitched and rolled.
        let tilt = RotationMatrix(rows: SIMD3(1, 0, 0), SIMD3(0, cosd(23), -sind(23)), SIMD3(0, sind(23), cosd(23)))
        let roll = RotationMatrix(rows: SIMD3(cosd(11), 0, sind(11)), SIMD3(0, 1, 0), SIMD3(-sind(11), 0, cosd(11)))
        let p = SkyProjector(
            attitude: DeviceAttitude(coreMotionRotationMatrix: roll * tilt * levelFacing(147).referenceToDevice),
            intrinsics: camera)
        for u in stride(from: 12.0, through: 3012, by: 500) {
            for v in stride(from: 16.0, through: 4016, by: 500) {
                let sky = p.unproject(PixelPoint(u: u, v: v))
                expectPixel(p.project(sky), u, v)
                let back = p.unproject(try #require(p.project(sky).pixel))
                let gap = back.enuVector - sky.enuVector
                #expect((gap * gap).sum().squareRoot() < 1e-12)
            }
        }
    }

    @Test("portrait intrinsics from the landscape buffer agree with a landscape projection")
    func landscapeBufferRotation() {
        let (fxL, fyL, cxL, cyL, wL, hL) = (2905.0, 2897.0, 2003.0, 1521.0, 4032.0, 3024.0)
        let portrait = CameraIntrinsics.portrait(fromLandscapeBuffer: fxL, fy: fyL, cx: cxL, cy: cyL, width: wL, height: hL)
        #expect(portrait.width == 3024 && portrait.height == 4032)
        let p = SkyProjector(attitude: levelFacing(200), intrinsics: portrait)
        for sky in [(0.0, 200.0), (12, 215), (-8, 190), (25, 180)] {
            let position = HorizontalPosition(altitudeDeg: sky.0, azimuthDeg: sky.1)
            let d = p.attitude.device(position)
            // Buffer axes: +u = device −Y, +v = device −X, forward = device −Z.
            let uL = fxL * -d.y / -d.z + cxL, vL = fyL * -d.x / -d.z + cyL
            expectPixel(p.project(position), hL - vL, uL)
        }
    }

    @Test("aspect-fill intrinsics map image pixels into the view")
    func aspectFill() {
        let view = camera.aspectFilled(toWidth: 390, height: 844)
        let s = max(390 / 3024.0, 844 / 4032.0)
        let image = SkyProjector(attitude: levelFacing(0), intrinsics: camera)
        let screen = SkyProjector(attitude: levelFacing(0), intrinsics: view)
        for sky in [(0.0, 0.0), (5, 3), (-2, 355)] {
            let position = HorizontalPosition(altitudeDeg: sky.0, azimuthDeg: sky.1)
            let ip = image.project(position).pixel!
            expectPixel(screen.project(position), ip.u * s - (3024 * s - 390) / 2, ip.v * s - (4032 * s - 844) / 2)
        }
        #expect(abs(view.cx - 195) < 1e-9 && abs(view.cy - 422) < 1e-9)
    }

    @Test("focal length from the long-side field of view")
    func fieldOfView() {
        let c = CameraIntrinsics(longSideFieldOfViewDeg: 69.4, width: 3024, height: 4032)
        #expect(abs(c.fx - 2016 / tand(34.7)) < 1e-9)
        #expect(c.fx == c.fy && c.cx == 1512 && c.cy == 2016)
    }

    @Test("a closed great circle splits into runs and never joins across the back")
    func pathClipping() {
        let p = SkyProjector(attitude: levelFacing(0), intrinsics: camera)
        let front = stride(from: -80.0, through: 80, by: 10).map { HorizontalPosition(altitudeDeg: 0, azimuthDeg: $0) }
        let single = p.projectPath(front)
        #expect(single.count == 1 && single[0].count == 17)

        // The whole horizon, 0…350° and closed: the front half, split at 0°.
        let ring = stride(from: 0.0, to: 360, by: 10).map { HorizontalPosition(altitudeDeg: 0, azimuthDeg: $0) }
        let runs = p.projectPath(ring, closed: true)
        #expect(runs.map(\.count) == [10, 10])
        // Each run ends where the chord from 80° to 90° (and 270° to 280°)
        // meets z = 0.01, some 290 000 px off to the side.
        let t = (0.01 - cosd(80)) / (cosd(90) - cosd(80))
        let clipOffset = 2900 * (sind(80) + (sind(90) - sind(80)) * t) / 0.01
        #expect(abs(runs[0].last!.u - (1512 + clipOffset)) < 1e-3)
        #expect(abs(runs[1].first!.u - (1512 - clipOffset)) < 1e-3)
        #expect(runs.joined().allSatisfy { abs($0.v - 2016) < 1e-6 })
    }
}

private func maxDifference(_ a: DeviceAttitude, _ b: DeviceAttitude) -> Double {
    let x = a.referenceToDevice, y = b.referenceToDevice
    let diffs: [SIMD3<Double>] = [x.row1 - y.row1, x.row2 - y.row2, x.row3 - y.row3]
    return diffs.map { Swift.max(abs($0.x), abs($0.y), abs($0.z)) }.max()!
}
