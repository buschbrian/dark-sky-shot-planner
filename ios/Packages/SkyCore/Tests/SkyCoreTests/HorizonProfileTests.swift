import Foundation
import Testing
@testable import SkyCore

/// Mirrors `app/tests/horizon.test.ts` (HorizonProfile).
@Suite("Horizon profile")
struct HorizonProfileTests {
    @Test("the bundled Candlestick Camp profile matches its README")
    func candlestick() throws {
        let p = try HorizonProfile.bundled("candlestick-camp")
        #expect(p.samples.count == 360)
        #expect(p.minAltitudeDeg == 1.024)
        #expect(p.maxAltitudeDeg == 8.7)
        #expect(p.altitudeDeg(atAzimuth: 326) == 1.024)
        #expect(p.altitudeDeg(atAzimuth: 14) == 8.7)
        // README: "The 1° file interpolates to 4.91° there" (azimuth 82.60°).
        #expect(abs(p.altitudeDeg(atAzimuth: 82.6) - 4.9142) < 1e-4)
    }

    @Test func wrapsAcrossNorth() throws {
        let p = try HorizonProfile.bundled("candlestick-camp")
        let between = (4.418 + 4.396) / 2
        #expect(abs(p.altitudeDeg(atAzimuth: 359.5) - between) < 1e-12)
        #expect(abs(p.altitudeDeg(atAzimuth: -0.5) - between) < 1e-12)
        #expect(p.altitudeDeg(atAzimuth: 360) == 4.396)
        #expect(p.altitudeDeg(atAzimuth: 720 + 14) == 8.7)
    }

    @Test func interpolatesUnevenSamples() throws {
        let p = try HorizonProfile(samples: [
            .init(azimuthDeg: 10, altitudeDeg: 2),
            .init(azimuthDeg: 100, altitudeDeg: 11),
            .init(azimuthDeg: 300, altitudeDeg: -1),
        ])
        #expect(abs(p.altitudeDeg(atAzimuth: 55) - 6.5) < 1e-12)
        #expect(abs(p.altitudeDeg(atAzimuth: 200) - 5) < 1e-12)
        #expect(abs(p.altitudeDeg(atAzimuth: 5) - (-1 + 3.0 * 65 / 70)) < 1e-12)
        #expect(HorizonProfile.flat(3).altitudeDeg(atAzimuth: 123) == 3)
    }

    @Test func rejectsMalformedFiles() {
        let h = HorizonProfile.csvHeader
        #expect(throws: HorizonProfile.ParseError.badHeader("az,alt")) { try HorizonProfile.parse(csv: "az,alt\n0,1\n") }
        #expect(throws: HorizonProfile.ParseError.badRow(line: 2, text: "0,x")) { try HorizonProfile.parse(csv: "\(h)\n0,x\n") }
        #expect(throws: HorizonProfile.ParseError.azimuthsNotIncreasing(line: 3)) { try HorizonProfile.parse(csv: "\(h)\n0,1\n0,2\n") }
        #expect(throws: HorizonProfile.ParseError.azimuthOutOfRange(line: 2, azimuthDeg: 360)) { try HorizonProfile.parse(csv: "\(h)\n360,1\n") }
        #expect(throws: HorizonProfile.ParseError.altitudeOutOfRange(line: 2, altitudeDeg: 91)) { try HorizonProfile.parse(csv: "\(h)\n0,91\n") }
        #expect(throws: HorizonProfile.ParseError.empty) { try HorizonProfile.parse(csv: "\(h)\n") }
        #expect((try? HorizonProfile.parse(csv: "\(h)\r\n0,1\r\n90,2\r\n"))?.samples.count == 2)
    }

    @Test("CSV output parses back to the same profile")
    func roundTrip() throws {
        let p = try HorizonProfile.bundled("candlestick-camp")
        #expect(try HorizonProfile.parse(csv: p.csv()) == p)
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(HorizonProfile.self, from: data) == p)
    }
}
