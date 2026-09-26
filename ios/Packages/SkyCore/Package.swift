// swift-tools-version: 6.2
import Foundation
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

// With only the Command Line Tools selected (no Xcode), SwiftPM does not pass
// swift-testing's macro plugin directory, so no @Test expands. Add it there
// only; under Xcode this is a no-op. Remove once Xcode is the toolchain.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
let testSwiftSettings = swiftSettings
    + (developerDir?.hasPrefix("/Library/Developer/CommandLineTools") == true
        && FileManager.default.fileExists(atPath: cltTestingPlugins)
        ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])] : [])

let package = Package(
    name: "SkyCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SkyCore", targets: ["SkyCore"]),
    ],
    targets: [
        .target(
            name: "CAstronomy",
            exclude: ["LICENSE", "VENDORED.md"]
        ),
        .target(
            name: "SkyCore",
            dependencies: ["CAstronomy"],
            resources: [
                .copy("Resources/app-config.json"),
                .copy("Resources/conditions-thresholds.json"),
                .copy("Resources/horizon-profiles"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SkyCoreTests",
            dependencies: ["SkyCore"],
            swiftSettings: testSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
