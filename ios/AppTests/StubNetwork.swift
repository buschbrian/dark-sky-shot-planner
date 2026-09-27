import Foundation
@testable import DarkSky
import SkyCore

/// Answers every request of a stubbed session from `StubNetwork.handler`, and
/// records what was asked. Suites using it run `.serialized`: one handler at a time.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubNetwork.record(request)
        do {
            let (status, headers, body) = try StubNetwork.answer(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum StubNetwork {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, [String: String], Data)

    nonisolated(unsafe) private static var handler: Handler = { _ in throw URLError(.notConnectedToInternet) }
    nonisolated(unsafe) private static var log: [URLRequest] = []
    private static let lock = NSLock()

    static func install(_ h: @escaping Handler) {
        lock.withLock {
            handler = h
            log = []
        }
    }

    static func record(_ r: URLRequest) { lock.withLock { log.append(r) } }
    static func answer(_ r: URLRequest) throws -> (Int, [String: String], Data) { try lock.withLock { handler }(r) }
    static var requests: [URLRequest] { lock.withLock { log } }
    static func requests(host: String) -> [URLRequest] { requests.filter { $0.url?.host() == host } }

    static func session() -> URLSession {
        let config = ConditionsClient.sessionConfiguration()
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static let workerHost = "worker.stub.test"
    static let workerBase = URL(string: "https://\(workerHost)")!

    static let offline: Handler = { _ in throw URLError(.notConnectedToInternet) }

    /// `Date` header text for `date`.
    static func httpDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.string(from: date)
    }

    /// A small Worker `/v1/conditions` body for `request`: HRRR cloud, clear.
    static func workerBody(_ request: ConditionsRequest, nextUpdate: Date?, cloud: Double = 5, withNearTerm: Bool = false) -> Data {
        let iso = ISO8601DateFormatter()
        let hours = stride(from: request.start.timeIntervalSince1970, through: request.end.timeIntervalSince1970, by: 3600)
            .map { iso.string(from: Date(timeIntervalSince1970: $0)) }
        let now = iso.string(from: .now)
        var json: [String: Any] = [
            "cell": ["lat": request.cell.latitude, "lon": request.cell.longitude, "rounding_deg": 0.05],
            "window": ["start_utc": iso.string(from: request.start), "end_utc": iso.string(from: request.end)],
            "generated_utc": now,
            "attribution": ["stub"],
            "fields": [
                "cloud_cover_total": [
                    "unit": "%", "source": "Open-Meteo", "status": "ok", "fetched_utc": now,
                    "series": [[
                        "model": "hrrr", "model_run_utc": iso.string(from: Date.now.addingTimeInterval(-3600)),
                        "fetched_utc": now, "status": "ok", "values": hours.map { ["t": $0, "v": cloud] },
                    ]],
                ],
            ],
        ]
        if withNearTerm {
            let quarters = stride(from: request.start.timeIntervalSince1970, through: request.start.timeIntervalSince1970 + 3 * 3600, by: 900)
                .map { iso.string(from: Date(timeIntervalSince1970: $0)) }
            var fields = json["fields"] as! [String: Any]
            fields["wind_gust"] = [
                "unit": "km/h", "source": "Open-Meteo", "status": "ok", "fetched_utc": now,
                "series": [["model": "hrrr", "fetched_utc": now, "status": "ok", "values": hours.map { ["t": $0, "v": 9] }]],
                "series_15min": [[
                    "model": "hrrr", "resolution_minutes": 15, "fetched_utc": now, "status": "ok",
                    "values": quarters.map { ["t": $0, "v": 11] },
                ]],
            ]
            json["fields"] = fields
        }
        json["next_update_expected_utc"] = nextUpdate.map { iso.string(from: $0) } ?? NSNull()
        return try! JSONSerialization.data(withJSONObject: json)
    }

    /// Open-Meteo forecast and `meta.json` answers for the direct path.
    static func openMeteo(_ r: URLRequest) -> (Int, [String: String], Data)? {
        guard let url = r.url, url.host() == "api.open-meteo.com" else { return nil }
        if url.path().hasSuffix("meta.json") {
            let run = (Date.now.timeIntervalSince1970 / 3600).rounded(.down) * 3600 - 3600
            let body = #"{"last_run_initialisation_time":\#(Int(run)),"last_run_availability_time":\#(Int(run + 3000)),"update_interval_seconds":3600}"#
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let start = items.first { $0.name == "start_date" }?.value ?? ""
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "yyyy-MM-dd"
        let day = f.date(from: start) ?? .now
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let times = (0..<72).map { f.string(from: day.addingTimeInterval(Double($0) * 3600)) }
        let values = Array(repeating: 12, count: times.count)
        let hourly: [String: Any] = [
            "time": times, "cloud_cover": values, "cloud_cover_low": values, "cloud_cover_mid": values, "cloud_cover_high": values,
        ]
        let units = ["cloud_cover": "%", "cloud_cover_low": "%", "cloud_cover_mid": "%", "cloud_cover_high": "%"]
        let body = try! JSONSerialization.data(withJSONObject: ["hourly": hourly, "hourly_units": units])
        return (200, ["Content-Type": "application/json"], body)
    }
}
