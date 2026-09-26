public import Foundation

/// One Worker `/v1/conditions` response as the app received it. Offline, the app
/// renders the newest snapshot with its age (PLAN.md §Architecture). Persistence
/// belongs to the app target; this is only the value.
public struct ConditionsSnapshot: Sendable, Hashable, Codable {
    public let response: ConditionsResponse
    /// When this device received the response (not when the Worker fetched upstream).
    public let fetchedUTC: Date

    enum CodingKeys: String, CodingKey {
        case response
        case fetchedUTC = "fetched_utc"
    }

    public init(response: ConditionsResponse, fetchedUTC: Date) {
        self.response = response
        self.fetchedUTC = fetchedUTC
    }

    public init(workerJSON: Data, fetchedUTC: Date) throws {
        self.init(response: try ConditionsResponse.decode(workerJSON), fetchedUTC: fetchedUTC)
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
