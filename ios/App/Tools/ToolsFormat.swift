import Foundation
import SkyCore

nonisolated extension ExposureParameter {
    var label: String {
        switch self {
        case .focalLength: "Focal length"
        case .fNumber: "f-number"
        case .pixelPitch: "Pixel pitch"
        case .sensorWidth: "Sensor width"
        case .sensorHeight: "Sensor height"
        case .sensorDiagonal: "Sensor diagonal"
        case .imageWidth: "Image width"
        case .imageHeight: "Image height"
        case .declination: "Declination"
        case .npfK: "NPF k"
        case .cropFactor: "Crop factor"
        case .circleOfConfusion: "Circle of confusion"
        case .cocDivisor: "Circle-of-confusion divisor"
        case .focusDistance: "Focus distance"
        case .exposure: "Exposure"
        case .snrGain: "SNR gain"
        case .frames: "Frames"
        case .interval: "Interval"
        case .buffer: "Buffer"
        case .fps: "Frame rate"
        case .clipLength: "Clip length"
        case .eventDuration: "Event duration"
        }
    }

    var requirement: String {
        switch self {
        case .focalLength, .sensorWidth, .sensorHeight, .sensorDiagonal: "must be more than 0 mm"
        case .fNumber: "must be f/\(ToolsFormat.number(LensProfile.minimumFNumber)) or slower"
        case .pixelPitch: "must be more than 0 µm"
        case .imageWidth, .imageHeight: "must be at least 1 pixel"
        case .declination: "must be between −90° and +90°"
        case .npfK: "must be between \(ToolsFormat.number(StarExposure.npfKRange.lowerBound)) and \(ToolsFormat.number(StarExposure.npfKRange.upperBound))"
        case .cropFactor, .circleOfConfusion, .cocDivisor, .fps: "must be more than 0"
        case .focusDistance: "must be farther than the focal length"
        case .exposure, .interval: "must be more than 0 s"
        case .snrGain: "must be between 1× and \(ToolsFormat.number(Stacking.maxSNRGain))×"
        case .frames: "must be at least 1"
        case .buffer: "must be 0 s or more"
        case .clipLength: "must be more than 0 s and under a million frames"
        case .eventDuration: "must be long enough for at least one interval"
        }
    }
}

nonisolated extension ExposureError {
    /// What the owner reads when a calculator rejects an input; never "NaN".
    var message: String {
        switch self {
        case .invalid(let parameter, let value):
            let got = value.isFinite ? " (you entered \(ToolsFormat.number(value)))" : " Enter a number."
            return "\(parameter.label) \(parameter.requirement).\(got)"
        case .missingPixelPitch:
            return "Enter the image width and height in pixels, or the pixel pitch."
        case .fNumberWiderThanLens(let n, let max):
            return "f/\(ToolsFormat.number(n)) is wider than this lens opens (f/\(ToolsFormat.number(max)))."
        case .intervalTooShort(let interval, let minimum):
            return "An interval of \(ToolsFormat.duration(interval)) is shorter than exposure + buffer (\(ToolsFormat.duration(minimum)))."
        }
    }
}

nonisolated enum ToolsFormat {
    /// Galactic Center declination (Sgr A*, J2000), the default target.
    static let gcDeclinationText = String(format: "%.1f", Planner.gcDecDeg)

    /// Text to number; accepts a Unicode minus and a decimal comma. nil when not a finite number.
    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    /// A required input: unparseable text becomes NaN so SkyCore rejects it with a typed error.
    static func required(_ text: String) -> Double { parse(text) ?? .nan }

    /// An optional input: empty means "use the default" (nil).
    static func optional(_ text: String) -> Double? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : required(text)
    }

    static func number(_ v: Double, digits: Int = 2) -> String {
        guard v.isFinite else { return v > 0 ? "∞" : "unavailable" }
        return v.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func duration(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "no limit" }
        if t < 60 { return "\(number(t, digits: 1)) s" }
        let total = Int(t.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        if h > 0 { return m == 0 ? "\(h) h" : "\(h) h \(m) min" }
        return s == 0 ? "\(m) min" : "\(m) min \(s) s"
    }

    static func meters(_ m: Double) -> String {
        guard m.isFinite else { return "∞" }
        return "\(number(m, digits: m < 10 ? 2 : 1)) m"
    }

    static func limit(_ l: FocusLimit) -> String {
        switch l {
        case .meters(let m): meters(m)
        case .infinity: "∞ (infinity)"
        }
    }
}
