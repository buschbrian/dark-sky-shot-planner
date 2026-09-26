public import Foundation

/// One Worker `/v1/conditions` response as the app received it. Offline, the app
/// renders the newest snapshot with its age (PLAN.md §Architecture). Persistence
/// belongs to the app target; this is only the value.
public struct ConditionsSnapshot: Sendable, Hashable, Codable {
    public let response: ConditionsResponse
    /// When this device received the response (not when the Worker fetched upstream).
    /// A 304 never rewrites it: the body is still the one received then.
    public let fetchedUTC: Date
    /// The Worker's `ETag` for this body, sent back as `If-None-Match` (M11).
    public var etag: String? = nil
    /// Last time the Worker confirmed this body unchanged (a 304's `Date`).
    public var checkedUTC: Date? = nil

    enum CodingKeys: String, CodingKey {
        case response
        case fetchedUTC = "fetched_utc"
        case etag
        case checkedUTC = "checked_utc"
    }

    public init(response: ConditionsResponse, fetchedUTC: Date, etag: String? = nil, checkedUTC: Date? = nil) {
        self.response = response
        self.fetchedUTC = fetchedUTC
        self.etag = etag
        self.checkedUTC = checkedUTC
    }

    public init(workerJSON: Data, fetchedUTC: Date, etag: String? = nil) throws {
        self.init(response: try ConditionsResponse.decode(workerJSON), fetchedUTC: fetchedUTC, etag: etag)
    }

    public func age(at now: Date) -> TimeInterval {
        now.timeIntervalSince(fetchedUTC)
    }

    public func freshness(at now: Date, window: FreshnessWindow) -> Freshness {
        window.freshness(since: fetchedUTC, now: now)
    }

    /// The oldest time any available series describes, so the whole snapshot's
    /// age is never better than its oldest ingredient.
    public var oldestDataUTC: Date? {
        response.fields.values
            .flatMap(\.series)
            .filter { $0.status == .ok }
            .compactMap(\.asOfUTC)
            .min()
    }

    public static func newest(_ snapshots: some Sequence<ConditionsSnapshot>) -> ConditionsSnapshot? {
        snapshots.max { $0.fetchedUTC < $1.fetchedUTC }
    }

    public func encoded() throws -> Data {
        try WorkerJSON.encoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> ConditionsSnapshot {
        try WorkerJSON.decoder().decode(ConditionsSnapshot.self, from: data)
    }
}
