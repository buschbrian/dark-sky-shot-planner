import Foundation
import Testing
@testable import SkyCore

@Suite struct ConditionsRequestTests {
    @Test(arguments: [
        (38.3712, 38.35), (38.3751, 38.4), (-109.9624, -109.95), (-109.98, -110.0),
        (0.024, 0), (-0.024, 0), (89.99, 90), (-179.99, -180), (40.76, 40.75),
    ])
    func roundsToTheGrid(raw: Double, expected: Double) {
        #expect(ConditionsCell.round(raw) == expected)
    }

    @Test func everyRoundedValueSitsOnTheWorkerGrid() {
        // The Worker's gridCoord check: |steps * 0.05 - x| <= 1e-9 after Number(text).
        for i in 0..<2000 {
            let raw = -90 + Double(i) * 0.0901
            let text = ConditionsCell(latitude: raw, longitude: 0).latitudeText
            let x = Double(text)!
            let steps = (x / 0.05).rounded()
            #expect(abs(steps * 0.05 - x) <= 1e-9, "\(raw) -> \(text)")
            #expect(abs(x - raw) <= 0.025 + 1e-9)
        }
    }

    @Test func negativeZeroIsSentAsZero() {
        #expect(ConditionsCell(latitude: -0.01, longitude: -0.001).key == "0.00_0.00")
    }

    @Test func workerURLCarriesOnlyRoundedCoordinates() throws {
        let now = try ISO.date("2026-09-26T18:00:00Z")
        let window = DateInterval(start: try ISO.date("2026-09-26T22:10:00Z"), end: try ISO.date("2026-09-27T16:05:00Z"))
        let req = try ConditionsRequest.make(latitude: 38.371234, longitude: -109.962345, window: window, now: now).get()
        let url = req.workerURL(base: URL(string: "https://example.workers.dev")!)
        #expect(url.absoluteString == "https://example.workers.dev/v1/conditions?lat=38.35&lon=-109.95&start=2026-09-26T22:00:00Z&end=2026-09-27T17:00:00Z")
        #expect(!url.absoluteString.contains("38.37"))
        #expect(req.startDate == "2026-09-26")
        #expect(req.endDate == "2026-09-27")
    }

    @Test func endingExactlyAtMidnightDoesNotAskForTheNextDay() throws {
        let now = try ISO.date("2026-09-26T18:00:00Z")
        let window = DateInterval(start: try ISO.date("2026-09-26T10:00:00Z"), end: try ISO.date("2026-09-27T00:00:00Z"))
        let req = try ConditionsRequest.make(latitude: 38, longitude: -110, window: window, now: now).get()
        #expect(req.endDate == "2026-09-26")
    }

    @Test func refusesWhatTheWorkerWouldReject() throws {
        let now = try ISO.date("2026-09-26T18:00:00Z")
        func make(_ start: String, _ end: String) throws -> ConditionsRequest.Refusal? {
            let w = DateInterval(start: try ISO.date(start), end: try ISO.date(end))
            if case .failure(let r) = ConditionsRequest.make(latitude: 38, longitude: -110, window: w, now: now) { return r }
            return nil
        }
        #expect(try make("2026-09-26T00:00:00Z", "2026-09-28T01:00:00Z") == .windowTooLong)
        #expect(try make("2026-09-24T17:00:00Z", "2026-09-25T06:00:00Z") == .tooFarInThePast)
        #expect(try make("2026-10-12T00:00:00Z", "2026-10-12T19:00:00Z") == .beyondForecastHorizon)
        #expect(try make("2026-09-26T22:00:00Z", "2026-09-27T16:00:00Z") == nil)
    }

    @Test func nightWindowCoversDuskToDawnInTheSpotsZone() throws {
        let denver = TimeZone(identifier: "America/Denver")!
        let w = ConditionsRequest.nightWindow(NightDate(iso: "2026-09-26")!, in: denver)
        #expect(w.start == (try ISO.date("2026-09-26T22:00:00Z")))
        #expect(w.end == (try ISO.date("2026-09-27T16:00:00Z")))
        #expect(w.duration <= ConditionsRequest.maxWindow)
    }
}

@Suite struct PlaceInputTests {
    @Test func plainPairs() {
        #expect(PlaceInput.parse("38.35, -109.95") == PlaceInput(latitude: 38.35, longitude: -109.95))
        #expect(PlaceInput.parse(" 38.35 -109.95\n") == PlaceInput(latitude: 38.35, longitude: -109.95))
        #expect(PlaceInput.parse("38.35;-109.95") == PlaceInput(latitude: 38.35, longitude: -109.95))
        #expect(PlaceInput.parse("+38.1234567,-109.9876543") == PlaceInput(latitude: 38.12346, longitude: -109.98765))
    }

    @Test func hemisphereLetters() {
        #expect(PlaceInput.parse("38.35° N, 109.95° W") == PlaceInput(latitude: 38.35, longitude: -109.95))
        #expect(PlaceInput.parse("33.9 S 18.4 E") == PlaceInput(latitude: -33.9, longitude: 18.4))
        #expect(PlaceInput.parse("-38.35 S, 109.95 W") == nil, "a sign and a letter contradict each other")
    }

    @Test func webShareLinks() {
        let p = PlaceInput.parse("https://example.github.io/dark-sky-shot-planner/#lat=38.53&lon=-109.9&date=2026-08-22&layers=lp,land")
        #expect(p == PlaceInput(latitude: 38.53, longitude: -109.9, night: NightDate(iso: "2026-08-22")))
        #expect(PlaceInput.parse("#lat=38.53&lon=-109.90")?.night == nil)
        #expect(PlaceInput.parse("#lat=38.53&lon=-109.90&date=2026-02-30")?.night == nil, "a bad date is ignored, not fatal")
        #expect(PlaceInput.parse("#lat=38.53&lon=-109.90&date=2026-08-22")?.night == NightDate(iso: "2026-08-22"))
    }

    @Test func rejects() {
        for bad in ["", "hello", "91, 10", "10, 181", "38.35", "#lat=38.5", "#lat=abc&lon=1", "#lat=95&lon=1", "nan, 1", "1,2,3"] {
            #expect(PlaceInput.parse(bad) == nil, "\(bad)")
        }
    }
}
