import Foundation
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
