import Foundation
import Testing
@testable import SkyCore

@Suite("Aurora flag")
struct AuroraTests {
    let rule: AuroraRule
    let slc: Observer
    let glacier: Observer
    let darkness: TimeWindow
    let day: Date

    init() throws {
        rule = try AuroraRule.bundled()
        slc = try observer(40.76, -111.89)
        glacier = try observer(48.70, -113.90)
        day = try ISO.date("2026-10-10T00:00:00Z")
        darkness = TimeWindow(start: day.addingTimeInterval(2 * 3600), end: day.addingTimeInterval(11 * 3600))
    }

    /// Readings every 3 h from `day`, starting at `fromHour`.
    func readings(_ values: [Double], fromHour: Int = 0, kind: KpReading.Kind = .predicted) -> [KpReading] {
        values.enumerated().map { i, v in
            KpReading(start: day.addingTimeInterval(Double(fromHour + 3 * i) * 3600), kp: v, kind: kind)
        }
    }

    func outlook(_ obs: Observer, _ r: [KpReading], now: Date? = nil, next: Bool = false, dark: TimeWindow? = nil) -> AuroraOutlook {
        rule.outlook(obs, darkness: dark ?? darkness, readings: r, now: now ?? day, isNextDarkWindow: next)
    }

    @Test("the rule comes from config and matches the repo copy")
    func ruleFromConfig() throws {
        #expect(try AuroraRule.decode(thresholdsJSON: Repo.data("config/conditions-thresholds.json")) == rule)
        #expect(rule.visibleKp.map(\.noaaScale) == ["G2", "G3", "G4", "G5"])
    }

    @Test("geomagnetic latitude of the centred dipole")
    func geomagneticLatitude() throws {
        let pole = rule.geomagneticNorthPole
        #expect(abs(rule.geomagneticLatitude(try observer(pole.latDeg, pole.lonDeg)) - 90) < 1e-9)
        #expect(abs(rule.geomagneticLatitude(try observer(-pole.latDeg, pole.lonDeg + 180)) + 90) < 1e-9)
        // On the pole's meridian, geomagnetic latitude is geographic plus the pole's colatitude.
        #expect(abs(rule.geomagneticLatitude(try observer(40, pole.lonDeg)) - (40 + 90 - pole.latDeg)) < 1e-9)
        // Independent computation (Python, same formula and pole): SLC 47.563, Fairbanks 65.665, Hobart -49.548.
        #expect(abs(rule.geomagneticLatitude(slc) - 47.563) < 0.001)
        #expect(abs(rule.geomagneticLatitude(try observer(64.84, -147.72)) - 65.665) < 0.001)
        #expect(abs(rule.geomagneticLatitude(try observer(-42.88, 147.33)) + 49.548) < 0.001)
    }

    @Test("visible Kp by spot", arguments: [
        (40.76, -111.89, 7.67), // Salt Lake City, 47.6 geomagnetic
        (38.57, -109.55, 7.67), // Moab, 45.7
        (37.10, -113.58, 9.0), // St George, 43.8
        (48.70, -113.90, 5.67), // Glacier NP, 55.2
        (-42.88, 147.33, 7.67), // Hobart, -49.5: the southern oval by absolute latitude
    ])
    func visibleKpBySpot(_ lat: Double, _ lon: Double, _ kp: Double) throws {
        #expect(rule.visibleKpThreshold(try observer(lat, lon)) == kp)
    }

    @Test func equatorwardOfTheTableIsOutOfRange() throws {
        let honolulu = try observer(21.31, -157.86)
        #expect(rule.visibleKpThreshold(honolulu) == nil)
        guard case .outOfRange(let mlat) = outlook(honolulu, readings([9, 9, 9, 9, 9])) else {
            Issue.record("expected outOfRange"); return
        }
        #expect(mlat < 40)
    }

    @Test("a forecast interval in the dark window at or above the visible Kp raises the flag")
    func forecastInWindow() {
        let r = readings([2, 2, 7.67, 2])
        #expect(outlook(slc, r) == .possible(kp: 7.67, visibleKp: 7.67, basis: .forecastInWindow))
        let observed = readings([2, 2, 8, 2], kind: .estimated)
        #expect(outlook(slc, observed) == .possible(kp: 8, visibleKp: 7.67, basis: .observedInWindow))
    }

    @Test("below the visible Kp across the whole window is not expected; one third short is not enough")
    func belowThreshold() {
        let r = readings([2, 2, 7.33, 2])
        #expect(outlook(slc, r) == .notExpected(maxKp: 7.33, visibleKp: 7.67))
        #expect(outlook(glacier, r) == .possible(kp: 7.33, visibleKp: 5.67, basis: .forecastInWindow))
    }

    @Test("intervals touching the window's edges do not count")
    func windowEdges() {
        // 23:00-02:00 ends at dusk; 11:00-14:00 starts at dawn.
        let before = KpReading(start: day.addingTimeInterval(-1 * 3600), kp: 9, kind: .predicted)
        let after = KpReading(start: day.addingTimeInterval(11 * 3600), kp: 9, kind: .predicted)
        #expect(outlook(slc, [before, after] + readings([1, 1, 1], fromHour: 2)) == .notExpected(maxKp: 1, visibleKp: 7.67))
    }

    @Test("Kp that stops short of the window, or has a gap, is unavailable, not 'no aurora'")
    func incompleteCoverage() {
        #expect(outlook(slc, readings([1, 1, 1])) == .unavailable(.kpDoesNotCoverNight))
        var gap = readings([1, 1, 1, 1])
        gap.remove(at: 2)
        #expect(outlook(slc, gap) == .unavailable(.kpDoesNotCoverNight))
        #expect(outlook(slc, []) == .unavailable(.noKpData))
        #expect(rule.outlook(slc, darkness: nil, readings: readings([9]), now: day, isNextDarkWindow: true)
            == .unavailable(.noAstronomicalDarkness))
    }

    @Test("but a high interval inside a partly covered window still raises the flag")
    func partialCoverageButHigh() {
        #expect(outlook(slc, readings([1, 8])) == .possible(kp: 8, visibleKp: 7.67, basis: .forecastInWindow))
    }

    @Test("an observed interval replaces the forecast for the same interval")
    func observedOutranksForecast() {
        let forecast = readings([2, 2, 8, 2])
        let observed = [KpReading(start: forecast[2].start, kp: 3, kind: .observed)]
        #expect(outlook(slc, forecast + observed) == .notExpected(maxKp: 3, visibleKp: 7.67))
        #expect(outlook(slc, observed + forecast) == .notExpected(maxKp: 3, visibleKp: 7.67))
    }

    @Test("Kp observed now flags the next dark window only, and only while it is current")
    func observedNow() {
        let now = day.addingTimeInterval(-4 * 3600) // 20:00Z, before dusk
        let storm = [KpReading(start: day.addingTimeInterval(-6 * 3600), kp: 8, kind: .observed)]
        let quietNight = readings([1, 1, 1, 1])
        #expect(outlook(slc, storm + quietNight, now: now, next: true)
            == .possible(kp: 8, visibleKp: 7.67, basis: .observedNow))
        #expect(outlook(slc, storm + quietNight, now: now, next: false) == .notExpected(maxKp: 1, visibleKp: 7.67))
        // Ended more than one interval ago: history, not "now".
        let later = day.addingTimeInterval(1 * 3600)
        #expect(outlook(slc, storm + quietNight, now: later, next: true) == .notExpected(maxKp: 1, visibleKp: 7.67))
        // A predicted value is never "observed now".
        let predicted = [KpReading(start: storm[0].start, kp: 8, kind: .predicted)]
        #expect(outlook(slc, predicted + quietNight, now: now, next: true) == .notExpected(maxKp: 1, visibleKp: 7.67))
    }

    @Test func workerKinds() {
        #expect(KpReading.Kind(worker: nil) == .observed)
        #expect(KpReading.Kind(worker: "observed") == .observed)
        #expect(KpReading.Kind(worker: "estimated") == .estimated)
        #expect(KpReading.Kind(worker: "predicted") == .predicted)
        #expect(KpReading.Kind(worker: "something new") == .predicted)
    }
}
