import Foundation
import SkyCore
import SwiftData

/// A saved place. Owned by the Spots screen (M8); other screens only read it.
@Model
final class Spot {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneID: String
    var notes: String
    /// `azimuth_deg,horizon_alt_deg` CSV, the `config/horizon-profiles/` format.
    var horizonCSV: String?
    var createdAt: Date

    // M8/M9 additions. Every one has a default so SwiftData migrates lightweight.
    /// Where the profile came from (measured, imported file, computed from terrain tiles).
    var horizonSource: String? = nil
    var horizonUpdatedAt: Date? = nil
    /// The one spot the widget shows.
    var isPinned: Bool = false
    /// JSON `SpotWeek`: the last 7-night check, shown with its age.
    var weekData: Data? = nil
    /// Last check that got usable results (`CheckOutcome.counts`).
    var lastCheckedAt: Date? = nil
    var lastCheckedInBackground: Bool = false
    /// Last attempt of any outcome, and that outcome (`CheckOutcome` raw value).
    var lastAttemptAt: Date? = nil
    var lastAttemptOutcome: String? = nil
    /// "Alert me when a night this week is Go at this spot."
    var alertGoThisWeek: Bool = false
    /// Night ISO dates already notified, so a Go night alerts once.
    var alertNotifiedNights: [String] = []

    init(name: String, latitude: Double, longitude: Double, timeZoneID: String,
         notes: String = "", horizonCSV: String? = nil, createdAt: Date = .now) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
        self.notes = notes
        self.horizonCSV = horizonCSV
        self.createdAt = createdAt
    }

    var place: Place {
        Place(name: name, latitude: latitude, longitude: longitude, timeZoneID: timeZoneID)
    }

    var horizonProfile: HorizonProfile? {
        horizonCSV.flatMap { try? HorizonProfile.parse(csv: $0) }
    }

    var lastOutcome: CheckOutcome? { lastAttemptOutcome.flatMap(CheckOutcome.init(rawValue:)) }

    var week: SpotWeek? {
        get { weekData.flatMap { try? SpotWeek.decode($0) } }
        set { weekData = try? newValue?.encoded() }
    }
}

/// Camera + lens profile for the exposure tools (M10), entered by the owner.
@Model
final class Gear {
    var name: String
    /// JSON of SkyCore `CameraProfile` / `LensProfile`.
    var cameraJSON: Data
    var lensJSON: Data
    var createdAt: Date

    init(name: String, cameraJSON: Data, lensJSON: Data, createdAt: Date = .now) {
        self.name = name
        self.cameraJSON = cameraJSON
        self.lensJSON = lensJSON
        self.createdAt = createdAt
    }
}
