import Foundation
import Testing
@testable import SkyCore

/// Unit checks that mirror `app/tests/skyevents.test.ts` and `showers.test.ts`
/// where the golden file cannot reach (malformed rows, formatting edge cases).
@Suite("Curated sky-events file")
struct CuratedEventsTests {
    let good: [String: Any] = [
        "id": "x", "name": "X", "kind": "meteor_shower",
        "active_from": "2026-01-01", "active_to": "2026-01-10", "peak_utc": "2026-01-05T00:00:00Z",
        "radiant_ra_hours": 1, "radiant_dec_deg": 2,
        "source_url": "https://example.org/x", "verified_on": "2026-01-01",
    ]

    func parse(_ rows: [[String: Any]]) -> CuratedLoadResult {
        CuratedEvents.parse(object: ["events": rows])
    }

    func with(_ changes: [String: Any]) -> [String: Any] {
        good.merging(changes) { _, new in new }
    }

    @Test("the bundled file parses with no problems, every row sourced")
    func bundled() {
        let r = CuratedEvents.bundled
        #expect(r.problems.isEmpty)
        #expect(!r.events.isEmpty)
        for e in r.events { #expect(e.sourceURL.hasPrefix("https://")) }
        for e in r.events where e.kind == .meteorShower {
            #expect(e.radiant != nil && e.peakUtc != nil)
        }
    }

    @Test("unverified rows stay unverified and say why in their notes")
    func unverified() {
        let ids = CuratedEvents.bundled.events.filter { $0.verifiedOn == nil }.map(\.id)
        #expect(ids.contains("leonids-2026") && ids.contains("geminids-2026"))
        for e in CuratedEvents.bundled.events where e.verifiedOn == nil {
            #expect(e.notes.lowercased().contains("approximate"))
        }
    }

    @Test("rows are anchored at 12:00 UTC so the calendar day survives west of UTC")
    func middayAnchors() {
        for e in CuratedEvents.bundled.events {
            #expect(JSTime.utcCalendar.component(.hour, from: e.activeFrom) == 12)
            #expect(e.activeTo >= e.activeFrom)
        }
    }

    @Test func dropsShowerWithoutRadiant() {
        let r = parse([with(["radiant_ra_hours": NSNull(), "radiant_dec_deg": NSNull()])])
        #expect(r.events.isEmpty)
        #expect(r.problems.first?.contains("needs a radiant") == true)
    }

    @Test func dropsRowWithoutSource() {
        let r = parse([with(["source_url": ""])])
        #expect(r.events.isEmpty)
        #expect(r.problems.first?.contains("source_url") == true)
    }

    @Test func dropsDuplicateKeepsFirst() {
        let r = parse([good, with(["name": "Y"])])
        #expect(r.events.map(\.name) == ["X"])
        #expect(r.problems.first?.contains("duplicate id") == true)
    }

    @Test func dropsUnknownKind() {
        #expect(parse([with(["kind": "eclipse"])]).problems.first?.contains("unknown kind \"eclipse\"") == true)
    }

    @Test func rejectsReversedRange() {
        #expect(parse([with(["active_to": "2025-12-01"])]).problems.first?.contains("active_from/active_to") == true)
    }

    @Test func rejectsBadPeak() {
        #expect(parse([with(["peak_utc": "soon"])]).problems.first?.contains("peak_utc") == true)
    }

    @Test func survivesNoEventsArray() {
        #expect(CuratedEvents.parse(object: [String: Any]()).problems.count == 1)
        #expect(CuratedEvents.parse(object: nil).problems.count == 1)
    }

    @Test func blankVerifiedOnIsUnverified() {
        let r = parse([with(["verified_on": NSNull()])])
        #expect(r.problems.isEmpty)
        #expect(r.events.first?.verifiedOn == nil)
    }

    @Test("a JSON boolean is not a number")
    func booleanIsNotANumber() {
        #expect(parse([with(["radiant_ra_hours": true])]).problems.first?.contains("needs a radiant") == true)
    }

    @Test("the active span covers the whole last day")
    func activeSpan() throws {
        let draconids = try #require(CuratedEvents.bundled.events.first { $0.id == "draconids-2026" })
        #expect(draconids.activeSpan.start == (try ISO.date("2026-10-06T00:00:00Z")))
        #expect(draconids.activeSpan.end == (try ISO.date("2026-10-11T00:00:00Z")))
    }

    @Test("distance Millcreek to Great Basin, and zero for the same point")
    func distance() {
        let km = CuratedEvents.distanceKm(40.687, -111.824, 39.006, -114.22)
        #expect(km > 250 && km < 300)
        #expect(CuratedEvents.distanceKm(40, -111, 40, -111) == 0)
    }
}

@Suite("Meteor showers at the observer")
struct MeteorShowerTests {
    let millcreek = try! Observer(latitude: 40.687, longitude: -111.824, heightMeters: 1400)
    let orionids = MeteorShowers.Radiant(raHours: 6.3, decDeg: 16)

    @Test("a morning peak belongs to the night that began the evening before")
    func eveningKeying() throws {
        let evening = MeteorShowers.evening(for: try ISO.date("2026-10-23T06:54:00Z"), longitude: millcreek.longitude)
        let lmt = evening.addingTimeInterval(millcreek.longitude / 15 * 3600)
        #expect(lmt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).hasPrefix("2026-10-22T21"))
        let dusk = MeteorShowers.evening(for: try ISO.date("2026-10-23T02:00:00Z"), longitude: millcreek.longitude)
        let smallHours = MeteorShowers.evening(for: try ISO.date("2026-10-23T09:00:00Z"), longitude: millcreek.longitude)
        #expect(dusk == smallHours)
    }

    @Test("transit altitude is 90 − |latitude − declination|")
    func transitAltitude() throws {
        var best = -90.0
        let day = try ISO.date("2026-10-23T00:00:00Z")
        for m in stride(from: 0, to: 24 * 60, by: 5) {
            best = max(best, MeteorShowers.radiantAltitudeDeg(millcreek, orionids, at: day.addingTimeInterval(Double(m) * 60)))
        }
        #expect(abs(best - (90 - abs(millcreek.latitude - orionids.decDeg))) < 0.6)
    }

    @Test("a northern radiant is unobservable from 40°S")
    func southern() throws {
        let a = try MeteorShowers.assess(
            try Observer(latitude: -40, longitude: -71), .init(raHours: 17.5, decDeg: 54),
            peak: try ISO.date("2026-10-09T01:00:00Z"),
            activeFrom: try ISO.date("2026-10-06T00:00:00Z"), activeTo: try ISO.date("2026-10-11T00:00:00Z"))
        #expect(!a.observableHere)
        #expect(a.peakNight.usableMinutes == 0)
    }
}

@Suite("JavaScript number rendering")
struct JSFormatTests {
    @Test func number() {
        #expect(JSFormat.number(60) == "60")
        #expect(JSFormat.number(65.3) == "65.3")
        #expect(JSFormat.number(-0.0) == "0")
        #expect(JSFormat.number(0.171) == "0.171")
    }

    @Test("toFixed rounds the exact binary value, exact ties away from zero")
    func fixed() {
        #expect(JSFormat.fixed(2.25, 1) == "2.3")   // exact tie
        #expect(JSFormat.fixed(0.35, 1) == "0.3")   // 0.34999… in binary
        #expect(JSFormat.fixed(1.005, 2) == "1.00") // 1.00499… in binary
        #expect(JSFormat.fixed(9.96, 1) == "10.0")
        #expect(JSFormat.fixed(0.171, 3) == "0.171")
        #expect(JSFormat.fixed(-0.04, 1) == "-0.0")
        #expect(JSFormat.fixed(0, 2) == "0.00")
    }
}
