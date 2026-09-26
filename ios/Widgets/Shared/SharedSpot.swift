import Foundation
import SkyCore

// Compiled into both the app and the widget extension (project.yml).

/// One night's verdict as stored on a spot and handed to the widget: the
/// level, the factor that set it, and where that factor's number came from.
nonisolated struct VerdictSummary: Codable, Hashable, Sendable {
    enum Cause: String, Codable, Sendable { case rating, incompleteData, staleData }

    let level: VerdictLevel
    let cause: Cause
    let limitingLabel: String
    /// Formatted with its unit, or "unavailable".
    let limitingValue: String
    let limitingSource: String
    let limitingAsOf: Date?
    let freshness: Freshness
    let evaluatedAt: Date

    var headline: String {
        switch (level, cause) {
        case (.go, _): "Go"
        case (.noGo, _): "No-go"
        case (.marginal, .incompleteData): "Marginal — incomplete data"
        case (.marginal, .staleData): "Marginal — stale data"
        case (.marginal, .rating): "Marginal"
        }
    }

    var shortLevel: String {
        switch level {
        case .go: "Go"
        case .marginal: "Marginal"
        case .noGo: "No-go"
        }
    }

    /// "Cloud cover (mean over window) 8 %", "Cloud cover unavailable".
    var limitingLine: String {
        limitingValue == "unavailable" ? "\(limitingLabel) unavailable" : "\(limitingLabel) \(limitingValue)"
    }
}

nonisolated struct NightSummary: Codable, Hashable, Sendable, Identifiable {
    /// `NightDate.iso`.
    let night: String
    /// Flat (mathematical) horizon; nil when the astronomy failed.
    let moonFreeMinutes: Int?
    /// With the spot's horizon profile; nil without one.
    let skylineMoonFreeMinutes: Int?
    let verdict: VerdictSummary?

    var id: String { night }
    var date: NightDate? { NightDate(iso: night) }
    /// The number the owner plans with: above the skyline when there is one.
    var headlineMinutes: Int? { skylineMoonFreeMinutes ?? moonFreeMinutes }
}

/// The last 7-night check of one spot.
nonisolated struct SpotWeek: Codable, Hashable, Sendable {
    let checkedAt: Date
    let terrainAware: Bool
    let nights: [NightSummary]

    func night(_ date: NightDate) -> NightSummary? { nights.first { $0.night == date.iso } }

    func encoded() throws -> Data { try JSONEncoder.shared.encode(self) }
    static func decode(_ data: Data) throws -> SpotWeek { try JSONDecoder.shared.decode(SpotWeek.self, from: data) }
}

/// What the widget needs about the pinned spot. It computes the astronomy
/// itself (into its timeline) and takes only verdicts from here.
nonisolated struct PinnedSpotPayload: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String
    let horizonCSV: String?
    let week: SpotWeek?
    let writtenAt: Date
}

extension PinnedSpotPayload {
    /// Everything the widget draws, without check times: equal keys mean a
    /// reload would draw the same widget, so the app skips it.
    var contentKey: Data {
        struct Key: Encodable {
            let name: String, latitude: Double, longitude: Double, timeZoneID: String, horizonCSV: String?
            let nights: [NightSummary]
        }
        let nights = (week?.nights ?? []).map { n in
            NightSummary(night: n.night, moonFreeMinutes: n.moonFreeMinutes, skylineMoonFreeMinutes: n.skylineMoonFreeMinutes,
                         verdict: n.verdict.map {
                             VerdictSummary(level: $0.level, cause: $0.cause, limitingLabel: $0.limitingLabel,
                                            limitingValue: $0.limitingValue, limitingSource: $0.limitingSource,
                                            limitingAsOf: $0.limitingAsOf, freshness: $0.freshness, evaluatedAt: .distantPast)
                         })
        }
        return (try? JSONEncoder.shared.encode(Key(name: name, latitude: latitude, longitude: longitude,
                                                    timeZoneID: timeZoneID, horizonCSV: horizonCSV, nights: nights))) ?? Data()
    }
}

/// The App Group container shared by the app and the widget. Without the
/// entitlement (signing may not allow App Groups) every call degrades to nil
/// or false, and the widget says "Open Dark Sky to pin a spot".
nonisolated enum SharedStore {
    static let infoKey = "DSAppGroupIdentifier"
    static let widgetKind = "Tonight"

    static var groupIdentifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    static var containerURL: URL? {
        groupIdentifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static var payloadURL: URL? { containerURL?.appendingPathComponent("pinned-spot.json") }

    static func read() -> PinnedSpotPayload? {
        guard let url = payloadURL, let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder.shared.decode(PinnedSpotPayload.self, from: data),
              payload.version == PinnedSpotPayload.currentVersion else { return nil }
        return payload
    }

    /// Writes (or with nil, removes) the payload. False when there is no shared container.
    @discardableResult
    static func write(_ payload: PinnedSpotPayload?) -> Bool {
        guard let url = payloadURL else { return false }
        do {
            if let payload {
                try JSONEncoder.shared.encode(payload).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }
}

nonisolated extension JSONEncoder {
    static var shared: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

nonisolated extension JSONDecoder {
    static var shared: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
