import Foundation
import Testing
@testable import SkyCore

/// Parity with `app/tests/freshness.test.ts` (same config, same "today", same
/// expectations), plus the edges `freshnessOf` implies.
@Suite("Freshness (ADR-0006)")
struct FreshnessTests {
    static let webCfg = FreshnessWindow(layerId: "test", freshMaxDays: 400, agingMaxDays: 550, staleMaxDays: 800)
    static let today = try! ISO.date("2026-08-22T00:00:00Z")

    struct Case: Sendable, CustomTestStringConvertible {
        let date: String?
        let expected: Freshness
        var testDescription: String { "\(date ?? "nil") → \(expected)" }
    }

    @Test("web cases: fresh / aging / stale / unavailable", arguments: [
        Case(date: "2026-01-01", expected: .fresh),
        Case(date: "2025-03-01", expected: .aging),
        Case(date: "2024-06-01", expected: .stale),
        Case(date: nil, expected: .unavailable),
        Case(date: "garbage", expected: .unavailable),
    ])
    func webCases(_ c: Case) {
        #expect(Self.webCfg.freshness(publicationDate: c.date, today: Self.today) == c.expected)
    }

    @Test("edges and what `new Date(`${d}T00:00:00Z`)` accepts", arguments: [
        Case(date: "2025-07-18", expected: .fresh),   // exactly 400 days
        Case(date: "2025-07-17", expected: .aging),   // 401
        Case(date: "2025-02-18", expected: .aging),   // 550
        Case(date: "2025-02-17", expected: .stale),   // 551
        Case(date: "2020-01-01", expected: .stale),   // past stale_max stays stale, as in TS and Python
        Case(date: "2027-01-01", expected: .fresh),   // future
        Case(date: "2026-02-30", expected: .fresh),   // JS rolls over to 2026-03-02
        Case(date: "2026", expected: .fresh),
        Case(date: "2026-01", expected: .fresh),
        Case(date: "2026-13-01", expected: .unavailable),
        Case(date: "2026-01-32", expected: .unavailable),
        Case(date: "2026-01-00", expected: .unavailable),
        Case(date: "2026-1-1", expected: .unavailable),
        Case(date: "2026-01-01T00:00Z", expected: .unavailable),
        Case(date: "", expected: .unavailable),
    ])
    func edges(_ c: Case) {
        #expect(Self.webCfg.freshness(publicationDate: c.date, today: Self.today) == c.expected)
    }

    @Test("day overflow matches JS Date")
    func overflow() {
        #expect(FreshnessWindow.utcMidnight("2026-02-30") == (try? ISO.date("2026-03-02T00:00:00Z")))
        #expect(FreshnessWindow.utcMidnight("2026-04-31") == (try? ISO.date("2026-05-01T00:00:00Z")))
        #expect(FreshnessWindow.utcMidnight("1969-12-31") == (try? ISO.date("1969-12-31T00:00:00Z")))
    }

    @Test("labels match FRESHNESS_LABEL")
    func labels() {
        #expect(Freshness.stale.label.contains("verify"))
        #expect(Freshness.unavailable.label == "unavailable")
        #expect(Freshness.fresh.label == "fresh")
        #expect(Freshness.aging.label == "aging")
    }

    @Test("windows come from config/app-config.json, bundled copy included")
    func windowsFromConfig() throws {
        let original = try FreshnessConfig.decode(Repo.data("config/app-config.json"))
        let bundled = try FreshnessConfig.bundled()
        #expect(bundled == original)
        #expect(Set(bundled.layers.keys).isSuperset(of: ["light_pollution", "land_ownership", "darksky_places"]))
        #expect(try bundled.conditionsWindow().unit == .hours)
        for (key, w) in bundled.layers.merging(bundled.hourlyLayers, uniquingKeysWith: { a, _ in a }) {
            #expect(w.layerId == key)
            #expect(w.freshMax <= w.agingMax && w.agingMax <= w.staleMax)
        }
        #expect(bundled.layers.values.allSatisfy { $0.unit == .days })
        #expect(bundled.hourlyLayers.values.allSatisfy { $0.unit == .hours })
    }

    /// Live conditions age in whole elapsed hours, floored, against the
    /// `freshness_hours` window.
    @Test("instants age by whole elapsed hours against the conditions window")
    func instants() throws {
        let w = try FreshnessConfig.bundled().conditionsWindow()
        let now = Self.today
        func f(_ hoursAgo: Double) -> Freshness { w.freshness(since: now.addingTimeInterval(-hoursAgo * 3600), now: now) }
        let freshHours = w.freshMax + 1
        let agingHours = w.agingMax + 1
        #expect(f(0) == .fresh)
        #expect(f(-5) == .fresh)
        #expect(f(freshHours - 0.01) == .fresh)
        #expect(f(freshHours) == .aging)
        #expect(f(agingHours - 0.01) == .aging)
        #expect(f(agingHours) == .stale)
        #expect(f(w.staleMax + 30) == .stale)
        #expect(w.freshness(since: nil, now: now) == .unavailable)
    }

    @Test("an instant and its UTC date agree at midnight")
    func instantMatchesDate() {
        for d in ["2026-01-01", "2025-03-01", "2024-06-01"] {
            #expect(Self.webCfg.freshness(since: FreshnessWindow.utcMidnight(d), now: Self.today)
                    == Self.webCfg.freshness(publicationDate: d, today: Self.today))
        }
    }

    @Test("worst of several")
    func worst() {
        #expect(Freshness.worst([.fresh, .stale, .aging]) == .stale)
        #expect(Freshness.worst([.fresh, .unavailable]) == .unavailable)
        #expect(Freshness.worst([]) == .fresh)
    }
}

@Suite("Per-source hourly freshness for live conditions")
struct ConditionsFreshnessTests {

    @Test("each source is aged by its own schedule")
    func perSourceWindows() throws {
        let f = try FreshnessConfig.bundled().conditionsFreshness()
        let smokeIssue = try ISO.date("2026-09-25T03:00:00Z")
        let beforeNextIngest = try ISO.date("2026-09-26T04:00:00Z")
        #expect(f.window(forField: "smoke_column").freshness(since: smokeIssue, now: beforeNextIngest) == .fresh)
        #expect(f.window(forField: "cloud_cover_total").freshness(since: smokeIssue, now: beforeNextIngest) == .stale)
        #expect(f.window(forField: "pm2_5").layerId == "air_quality_forecast")
        #expect(f.window(forField: "no_such_field").layerId == FreshnessConfig.conditionsLayer)
        #expect(f.window(forField: nil).layerId == FreshnessConfig.conditionsLayer)
        #expect(f.byField.values.allSatisfy { $0.unit == .hours })
    }

    @Test("hourly layers list only real Worker fields, each once")
    func fieldListsMatchTheWorker() throws {
        let config = try FreshnessConfig.bundled()
        let fields = try WorkerContractTests.conditions().fields.keys
        #expect(Set(config.hourlyLayerForField.keys).isSubset(of: Set(fields)))
        let duplicate = Data(#"{"freshness_days":{},"freshness_hours":{"a":{"layer_id":"a","fields":["x"],"fresh_max_hours":1,"aging_max_hours":2,"stale_max_hours":3},"b":{"layer_id":"b","fields":["x"],"fresh_max_hours":1,"aging_max_hours":2,"stale_max_hours":3}}}"#.utf8)
        #expect(throws: DecodingError.self) { try FreshnessConfig.decode(duplicate) }
    }
}
