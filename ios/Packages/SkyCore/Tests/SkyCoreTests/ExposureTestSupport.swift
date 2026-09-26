@testable import SkyCore

/// |a − b| ≤ tolerance, and never true for NaN.
func approx(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}

/// Relative agreement, for values that span orders of magnitude.
func approxRel(_ a: Double, _ b: Double, _ fraction: Double) -> Bool {
    abs(a - b) <= fraction * abs(b)
}

func fullFrame(_ name: String = "36 × 24", widthPx: Int = 6000, heightPx: Int = 4000) throws -> CameraProfile {
    try CameraProfile(name: name, sensorWidthMM: 36, sensorHeightMM: 24,
                      resolution: PixelResolution(widthPx: widthPx, heightPx: heightPx))
}

/// A deterministic spread of real-world night gear for property tests.
enum GearGrid {
    static let fNumbers = [0.95, 1.4, 1.8, 2.0, 2.8, 4.0, 5.6, 8.0]
    static let focalLengths = [8.0, 14.0, 20.0, 24.0, 35.0, 50.0, 85.0, 135.0, 400.0]
    static let pitches = [0.8, 2.4, 3.76, 4.35, 5.93, 8.4]
    static let declinations = [-89.0, -60.0, -29.0, 0.0, 15.0, 45.0, 75.0, 89.0]
}
