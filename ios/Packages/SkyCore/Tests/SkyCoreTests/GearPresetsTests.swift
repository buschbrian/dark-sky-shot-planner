import Foundation
import Testing
@testable import SkyCore

/// `config/gear-presets.json` (ADR-0012): every row must become a valid
/// profile, carry its source and date, and agree with itself.
@Suite("Curated gear presets")
struct GearPresetsTests {
    let presets: GearPresets

    init() throws {
        presets = try GearPresets.bundled()
    }

    @Test func decodesEveryCategory() {
        #expect(presets.schemaVersion == 1)
        #expect(presets.cameras.count >= 60 && presets.lenses.count >= 70)
        for category in [GearPresets.Category.iphone, .fullFrame, .apsC, .mft] {
            #expect(!presets.cameras(in: category).isEmpty, "no \(category) cameras")
            #expect(!presets.lenses(in: category).isEmpty, "no \(category) lenses")
        }
        #expect(presets.cameras(in: .iphone).allSatisfy { $0.category == .iphone })
    }

    @Test func everyCameraIsAValidProfile() {
        for camera in presets.cameras {
            #expect(throws: Never.self, "\(camera.id)") { _ = try camera.profile() }
        }
    }

    @Test func everyLensIsAValidProfile() {
        for lens in presets.lenses {
            #expect(throws: Never.self, "\(lens.id)") { _ = try lens.profile() }
        }
    }

    @Test func everyRowCarriesSourceDateAndBasis() throws {
        let rows: [(String, String, String, String)] =
            presets.cameras.map { ($0.id, $0.sourceURL, $0.verifiedOn, $0.valueBasis) }
            + presets.lenses.map { ($0.id, $0.sourceURL, $0.verifiedOn, $0.valueBasis) }
        for (id, source, verified, basis) in rows {
            if source.hasPrefix("https://") || source.hasPrefix("http://") {
                #expect(URL(string: source)?.host() != nil, "\(id): bad source_url")
            } else {
                // A repo path, e.g. the owner's measured capture limits.
                #expect(FileManager.default.fileExists(atPath: Repo.root.appending(path: source).path()),
                        "\(id): source_url \(source) is neither a URL nor a repo file")
            }
            let day = try #require(try? Date(verified, strategy: .iso8601.year().month().day()), "\(id): verified_on")
            #expect(day <= .now, "\(id): verified_on is in the future")
            #expect(!basis.trimmingCharacters(in: .whitespaces).isEmpty, "\(id): value_basis")
        }
    }

    /// Stated pitch vs sensor width ÷ image width, within 5 %, unless the
    /// sensor size is labelled an optical-format estimate.
    @Test func pitchAgreesWithSensorSize() {
        for camera in presets.cameras where camera.sensorSizeBasis != .opticalFormatEstimate {
            let gap = abs(camera.derivedPixelPitchUM - camera.pixelPitchUM) / camera.pixelPitchUM
            #expect(gap <= 0.05, "\(camera.id): \(camera.pixelPitchUM) µm stated vs \(camera.derivedPixelPitchUM) µm derived")
        }
    }

    @Test func statedOrMeasuredPitchIsWhatTheProfileUses() throws {
        for camera in presets.cameras {
            let profile = try camera.profile()
            if camera.pixelPitchBasis == .sensorWidthOverPixels {
                #expect(profile.statedPixelPitchUM == nil)
                #expect(abs(profile.pixelPitchUM - camera.pixelPitchUM) < 0.006, "\(camera.id): rounded pitch drifted")
            } else {
                #expect(profile.statedPixelPitchUM == camera.pixelPitchUM, "\(camera.id)")
            }
        }
    }

    /// `docs/ios/CAPTURE-LIMITS.md`: EXIF 6.93 mm, 3.46 crop, 2.48 µm, NPF 8.6 s at k = 1.
    @Test func iPhone18ProMaxMainMatchesMeasuredNPF() throws {
        let text = try String(decoding: Repo.data("docs/ios/CAPTURE-LIMITS.md"), as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let match = try #require(text.firstMatch(of: /NPF limit of ([0-9.]+) s at k = 1/))
        let recorded = try #require(Double(match.1))
        #expect(recorded == 8.6)

        let row = try #require(presets.camera(id: "iphone-18-pro-max-main"))
        let lensRow = try #require(presets.lenses(for: row).first)
        #expect(row.pixelPitchBasis == .exifMeasured && lensRow.focalLengthBasis == .exifMeasured)
        let camera = try row.profile(), lens = try lensRow.profile()
        #expect(abs(camera.cropFactor - 3.46) < 0.01)
        let npf = try StarExposure.npf(camera: camera, lens: lens)
        #expect(abs(npf - recorded) < 0.05, "NPF \(npf) s")
    }

    @Test func idsAreUniqueAndPairsResolveBothWays() throws {
        let ids = presets.cameras.map(\.id) + presets.lenses.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids")
        for camera in presets.cameras {
            if camera.category == .iphone || camera.category == .ipad {
                #expect(!camera.pairsWith.isEmpty, "\(camera.id) has no lens")
                #expect(camera.mount == "fixed (built-in)")
            }
            for lensID in camera.pairsWith {
                let lens = try #require(presets.lens(id: lensID), "\(camera.id) -> missing \(lensID)")
                #expect(lens.pairsWith.contains(camera.id), "\(lensID) does not pair back to \(camera.id)")
                #expect(lens.category == camera.category)
            }
        }
        for lens in presets.lenses {
            for cameraID in lens.pairsWith {
                let camera = try #require(presets.camera(id: cameraID), "\(lens.id) -> missing \(cameraID)")
                #expect(camera.pairsWith.contains(lens.id))
            }
        }
    }

    @Test func excludedAndRenamedRowsAreAccountedFor() {
        let ids = Set(presets.cameras.map(\.id) + presets.lenses.map(\.id))
        #expect(!presets.excluded.isEmpty)
        for row in presets.excluded {
            #expect(!ids.contains(row.id), "\(row.id) is both excluded and present")
            #expect(["cameras", "lenses"].contains(row.table) && !row.reason.isEmpty, "\(row.id)")
        }
        for row in presets.renamed {
            #expect(ids.contains(row.to) && !ids.contains(row.from), "\(row.from) -> \(row.to)")
        }
    }

    @Test func lookupAndMountFilters() throws {
        let a7iv = try #require(presets.camera(id: "sony-a7-iv"))
        let sonyLenses = presets.lenses(for: a7iv)
        #expect(sonyLenses.contains { $0.id == "sigma-14-1.4-dgdn" })
        #expect(sonyLenses.allSatisfy { $0.mount.contains("Sony E") })
        #expect(!sonyLenses.contains { $0.category == .iphone })

        let sigma14 = try #require(presets.lens(id: "sigma-14-1.4-dgdn"))
        #expect(presets.cameras(for: sigma14).contains { $0.id == "sony-a7-iv" })

        let phone = try #require(presets.camera(id: "iphone-18-pro-max-main"))
        #expect(presets.lenses(for: phone).map(\.id) == ["iphone-18-pro-max-main-lens"])
        #expect(presets.camera(id: "no-such-camera") == nil)
    }
}
