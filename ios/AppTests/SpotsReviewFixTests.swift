import Foundation
import SkyCore
import Testing
@testable import DarkSky

/// Review 2026-09-26 (docs/ios/PERIODIC-REVIEW-2026-09-26.md): alerts only for
/// windows still ahead; the measured skyline belongs to its surveyed observer.
@MainActor
struct SpotsReviewFixTests {
    static let now = Date(timeIntervalSince1970: 1_790_500_000)

    static func night(_ id: String, go: Bool, until: Date?) -> NightSummary {
        NightSummary(
            night: id, moonFreeMinutes: 120, skylineMoonFreeMinutes: nil,
            verdict: go ? VerdictSummary(level: .go, cause: .rating, limitingLabel: "Cloud", limitingValue: "5 %",
                                         limitingSource: "test", limitingAsOf: nil, freshness: .fresh, evaluatedAt: now) : nil,
            usableUntil: until)
    }

    static func week(_ nights: [NightSummary]) -> SpotWeek {
        SpotWeek(checkedAt: now, terrainAware: false, nights: nights, requestedWindows: 1, fetchedWindows: 1, interrupted: false)
    }

    @Test("a Go night whose window ended (morning after) never alerts")
    func elapsedWindowIsNotEligible() {
        let w = Self.week([
            Self.night("2026-09-25", go: true, until: Self.now.addingTimeInterval(-3 * 3600)),
            Self.night("2026-09-26", go: true, until: Self.now.addingTimeInterval(14 * 3600)),
            Self.night("2026-09-27", go: true, until: nil),
            Self.night("2026-09-28", go: false, until: Self.now.addingTimeInterval(38 * 3600)),
            Self.night("2026-09-29", go: true, until: Self.now.addingTimeInterval(62 * 3600)),
        ])
        let eligible = SpotRefresh.eligibleGoNights(w, notified: ["2026-09-29"], now: Self.now).map(\.night)
        #expect(eligible == ["2026-09-26"])
    }

    @Test("the RMS comparison only runs at the surveyed observer; nearby reuse is labelled")
    func measuredProfileBelongsToItsObserver() throws {
        let o = MeasuredHorizons.candlestick
        #expect(MeasuredHorizons.isAtCandlestick(latitude: o.latitude, longitude: o.longitude))
        // The campsite field note, ~21 m north of the analysis point.
        #expect(MeasuredHorizons.isAtCandlestick(latitude: 38.374222, longitude: -109.965417))
        let nearby = (latitude: o.latitude + 0.0045, longitude: o.longitude)   // ~500 m north
        #expect(!MeasuredHorizons.isAtCandlestick(latitude: nearby.latitude, longitude: nearby.longitude))
        #expect(MeasuredHorizons.offersCandlestick(latitude: nearby.latitude, longitude: nearby.longitude))
        let source = MeasuredHorizons.candlestickSource(latitude: nearby.latitude, longitude: nearby.longitude)
        #expect(source.contains("reused") && source.contains("may differ"))
        #expect(MeasuredHorizons.candlestickSource(latitude: o.latitude, longitude: o.longitude) == MeasuredHorizons.candlestickSource)
        #expect(!MeasuredHorizons.offersCandlestick(latitude: o.latitude + 0.02, longitude: o.longitude))
    }
}
