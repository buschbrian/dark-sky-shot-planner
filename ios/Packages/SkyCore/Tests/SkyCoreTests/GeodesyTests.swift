import Foundation
import Testing
@testable import SkyCore

/// Ground distance between two points close together, in metres.
private func offsetMeters(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
    let r = Double.pi / 180
    let north = (a.latitude - b.latitude) * 111_320
    let dLon = Geodesy.signedAngle(a.longitude - b.longitude)
    let east = dLon * 111_320 * cos(a.latitude * r)
    return (north * north + east * east).squareRoot()
}

/// Azimuth tolerance that moves the far end of a line of length `s` by 1 mm,
/// capped at 1e-8°.
private func azimuthTolerance(_ s: Double) -> Double {
    min(1e-8, 0.001 / s * 180 / .pi)
}

private struct DirectCase: CustomTestStringConvertible, Sendable {
    let name: String
    let lat1, lon1, azi1, s12: Double
    let lat2, lon2, azi2: Double
    var testDescription: String { name }
}

/// Reference values. Tolerance is 1 mm on the endpoint, twice Vincenty's
/// stated 0.5 mm; published values are rounded, which that also covers.
private let references: [DirectCase] = [
    // Karney, "Algorithms for geodesics", J. Geodesy 87:43–55 (2013),
    // doi:10.1007/s00190-012-0578-z, Table 2 (WGS84): φ2, λ12, α2.
    DirectCase(name: "Karney 2013 Table 2", lat1: 40, lon1: 0, azi1: 30, s12: 10_000_000,
               lat2: 41.79331020506, lon2: 137.84490004377, azi2: 149.09016931807),
    // GeographicLib Python documentation, "Examples": 20 000 km SW of Perth,
    // printed as (32.11195529, -63.95925278); 8 decimals is ±0.6 mm.
    DirectCase(name: "GeographicLib docs, Perth 20 000 km", lat1: -32.06, lon1: 115.74, azi1: 225, s12: 20_000_000,
               lat2: 32.11195529, lon2: -63.95925278, azi2: .nan),
    // Mountain West lines: GeographicLib 2.1 Geodesic.WGS84.Direct (Karney's
    // reference implementation), run 2026-09-26.
    DirectCase(name: "Canyonlands, 128°, 25 km", lat1: 38.374031, lon1: -109.965416, azi1: 128, s12: 25_000,
               lat2: 38.23515519116, lon2: -109.74040186579, azi2: 128.13947341128),
    DirectCase(name: "Salt Lake City, due north, 1 km", lat1: 40.76, lon1: -111.89, azi1: 0, s12: 1_000,
               lat2: 40.76900500473, lon2: -111.89, azi2: 0),
    DirectCase(name: "Great Basin NP, 296.5°, 100 km", lat1: 38.98, lon1: -114.3, azi1: 296.5, s12: 100_000,
               lat2: 39.37730218573, lon2: -115.33864963363, azi2: 360 - 64.15617184269),
    DirectCase(name: "Glacier NP, due west, 400 km", lat1: 48.7, lon1: -113.8, azi1: 270, s12: 400_000,
               lat2: 48.57205754764, lon2: -119.22486583933, azi2: 360 - 94.07284196806),
    DirectCase(name: "Chiricahua, 160°, 50 km", lat1: 31.9, lon1: -109.3, azi1: 160, s12: 50_000,
               lat2: 31.47613467837, lon2: -109.12004104429, azi2: 160.09453214531),
]

@Suite("WGS84 geodesics (Vincenty) against published references")
struct GeodesyTests {
    @Test("direct problem matches the reference to 1 mm", arguments: references)
    fileprivate func direct(_ c: DirectCase) {
        let start = GeoCoordinate(latitude: c.lat1, longitude: c.lon1)
        let result = Geodesy.direct(from: start, azimuthDeg: c.azi1, distanceMeters: c.s12)
        let expected = GeoCoordinate(latitude: c.lat2, longitude: c.lon2)
        #expect(offsetMeters(result.end, expected) < 0.001, "\(result.end)")
        if !c.azi2.isNaN {
            #expect(abs(Geodesy.signedAngle(result.finalAzimuthDeg - c.azi2)) < azimuthTolerance(c.s12))
        }
    }

    @Test("inverse problem, Salt Lake City to Canyonlands (GeographicLib 2.1 Geodesic.WGS84.Inverse)")
    func inverseReference() throws {
        let result = try #require(Geodesy.inverse(
            from: GeoCoordinate(latitude: 40.76, longitude: -111.89),
            to: GeoCoordinate(latitude: 38.374031, longitude: -109.965416)))
        #expect(abs(result.distanceMeters - 312_270.150780) < 0.001)
        #expect(abs(result.initialAzimuthDeg - 147.40602782577) < azimuthTolerance(result.distanceMeters))
        #expect(abs(result.finalAzimuthDeg - 148.63228520180) < azimuthTolerance(result.distanceMeters))
    }

    @Test("inverse recovers Karney's Table 2 geodesic")
    func inverseKarney() throws {
        let result = try #require(Geodesy.inverse(
            from: GeoCoordinate(latitude: 40, longitude: 0),
            to: GeoCoordinate(latitude: 41.79331020506, longitude: 137.84490004377)))
        #expect(abs(result.distanceMeters - 10_000_000) < 0.001)
        #expect(abs(result.initialAzimuthDeg - 30) < 1e-8)
        #expect(abs(result.finalAzimuthDeg - 149.09016931807) < 1e-8)
    }

    @Test("direct then inverse returns the bearing and length at map scales")
    func roundTrip() throws {
        let pin = GeoCoordinate(latitude: 38.374031, longitude: -109.965416)
        for bearing in stride(from: 0.0, to: 360, by: 22.5) {
            for length in [500.0, 5_000, 50_000, 300_000] {
                let end = Geodesy.direct(from: pin, azimuthDeg: bearing, distanceMeters: length).end
                let back = try #require(Geodesy.inverse(from: pin, to: end))
                #expect(abs(back.distanceMeters - length) < 0.001)
                #expect(abs(Geodesy.signedAngle(back.initialAzimuthDeg - bearing)) < azimuthTolerance(length))
            }
        }
    }

    @Test("a densified path lies on the geodesic, from the pin to the endpoint")
    func path() throws {
        let pin = GeoCoordinate(latitude: 40.76, longitude: -111.89)
        let points = Geodesy.path(from: pin, azimuthDeg: 296.5, distanceMeters: 200_000, segments: 8)
        #expect(points.count == 9)
        #expect(points.first == pin)
        let end = Geodesy.direct(from: pin, azimuthDeg: 296.5, distanceMeters: 200_000).end
        #expect(try #require(points.last) == end)
        for (i, p) in points.enumerated().dropFirst() {
            let leg = try #require(Geodesy.inverse(from: pin, to: p))
            #expect(abs(leg.distanceMeters - 25_000 * Double(i)) < 0.001)
            #expect(abs(leg.initialAzimuthDeg - 296.5) < 1e-8)
        }
    }

    @Test func angleNormalization() {
        #expect(Geodesy.normalizedAzimuth(-10) == 350)
        #expect(Geodesy.normalizedAzimuth(360) == 0)
        #expect(Geodesy.normalizedAzimuth(725) == 5)
        #expect(Geodesy.signedAngle(190) == -170)
        #expect(Geodesy.signedAngle(180) == 180)
        #expect(Geodesy.signedAngle(-180) == 180)
        #expect(GeoCoordinate(latitude: 0, longitude: 190).longitude == -170)
    }
}
