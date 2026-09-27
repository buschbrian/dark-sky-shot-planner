import Foundation
import SkyCore

/// Curated meteor-shower radiants (`config/sky-events.json`) for the Sky view.
/// Drift and population index stay at their defaults: the curated file has neither.
enum CuratedRadiants {
    static let provider: StaticRadiants = StaticRadiants(ShowerRadiantRow.all().map {
        SkyRadiant(id: $0.id, name: $0.name, raDeg: $0.raDeg, decDeg: $0.decDeg,
                   activeFrom: $0.activeFrom, activeUntil: $0.activeUntil, peak: $0.peak, zhr: $0.zhr,
                   sourceURL: $0.sourceURL, verified: $0.verified)
    })
}
