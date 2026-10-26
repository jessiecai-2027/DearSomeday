//
//  BundleReadErrorTests.swift
//  DearSomedayTests
//
//  One test per §7.2 rejection case in BundleReader. Each writes a deliberately
//  broken bundle to a temp directory on disk and asserts BOTH:
//    • the specific BundleReadError, and
//    • that nothing was partially loaded — read threw and returned no
//      LoadedBundle, so no photo bytes or manifest leak out on failure.
//
//  Manifests here are hand-built with JSONSerialization so we can inject values
//  BundleWriter would never emit (bad schema version, duplicate orders, unknown
//  element types, …).
//

import Testing
import Foundation
@testable import DearSomeday

struct BundleReadErrorTests {

    // MARK: - Harness

    /// Outcome of a read expected to fail. `loaded` must stay nil — that's the
    /// "nothing partially loaded" assertion.
    private func readOutcome(at url: URL) -> (error: BundleReadError?, loaded: LoadedBundle?) {
        do {
            let bundle = try BundleReader.read(at: url)
            return (nil, bundle)
        } catch let error as BundleReadError {
            return (error, nil)
        } catch {
            return (nil, nil)
        }
    }

    private func assertRejects(
        _ url: URL,
        with expected: BundleReadError,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let outcome = readOutcome(at: url)
        #expect(outcome.error == expected, comment ?? "", sourceLocation: sourceLocation)
        // Never partially loaded: a failed read yields no bundle at all.
        #expect(outcome.loaded == nil, "read returned a bundle on failure", sourceLocation: sourceLocation)
    }

    // MARK: - Bundle construction

    private func makeBundleDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dfm-readerr-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeManifest(_ object: [String: Any], to bundleURL: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: bundleURL.appendingPathComponent("manifest.json"))
    }

    private func writePhotoFiles(_ names: [String], to bundleURL: URL) throws {
        let photosDir = bundleURL.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        for name in names {
            try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photosDir.appendingPathComponent(name))
        }
    }

    private func photo(_ file: String, _ order: Int) -> [String: Any] {
        ["file": file, "order": order]
    }

    private func stickerElement(type: String = "sticker") -> [String: Any] {
        [
            "id": UUID().uuidString,
            "type": type,
            "assetId": "washi-03",
            "position": ["x": 0.42, "y": 0.18],
            "rotation": -2.5,
            "scale": 1.0,
            "zIndex": 0,
        ]
    }

    /// A valid manifest dict; individual tests break one thing about it.
    private func baseManifest(
        schemaVersion: Int = 1,
        state: String = "sealed",
        photos: [[String: Any]],
        elements: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "schemaVersion": schemaVersion,
            "id": UUID().uuidString,
            "title": "T",
            "description": "D",
            "createdAt": "2026-01-01T00:00:00Z",
            "editableUntil": "2026-01-02T00:00:00Z",
            "unlockDate": "2026-06-01T00:00:00Z",
            "state": state,
            "photos": photos,
            "decoration": ["substrateId": "kraft-01", "elements": elements],
        ]
    }

    // MARK: - 1. manifest.json missing or unparseable

    @Test func missingManifestIsRejected() throws {
        let bundle = try makeBundleDir()
        try writePhotoFiles(["01.jpg"], to: bundle)   // photos but no manifest.json
        assertRejects(bundle, with: .manifestMissingOrUnparseable, "missing manifest")
    }

    @Test func unparseableManifestIsRejected() throws {
        let bundle = try makeBundleDir()
        try Data("{ this is not valid json".utf8)
            .write(to: bundle.appendingPathComponent("manifest.json"))
        assertRejects(bundle, with: .manifestMissingOrUnparseable, "garbage manifest")
    }

    // MARK: - 2. unknown schemaVersion

    @Test func unknownSchemaVersionIsRejected() throws {
        let bundle = try makeBundleDir()
        try writeManifest(baseManifest(schemaVersion: 999, photos: []), to: bundle)
        assertRejects(bundle, with: .unknownSchemaVersion(999))
    }

    // MARK: - 3. unknown element type

    @Test func unknownElementTypeIsRejected() throws {
        let bundle = try makeBundleDir()
        let manifest = baseManifest(photos: [], elements: [stickerElement(type: "unicorn")])
        try writeManifest(manifest, to: bundle)
        assertRejects(bundle, with: .unknownElementType("unicorn"))
    }

    // MARK: - 4. manifest references a photo file that isn't there

    @Test func missingPhotoFileIsRejected() throws {
        let bundle = try makeBundleDir()
        // Reference photos/01.jpg but never write it (no photos/ dir at all).
        try writeManifest(baseManifest(photos: [photo("photos/01.jpg", 0)]), to: bundle)
        assertRejects(bundle, with: .missingPhotoFile("photos/01.jpg"))
    }

    // MARK: - 5. photo file present but unreferenced

    @Test func unreferencedPhotoFileIsRejected() throws {
        let bundle = try makeBundleDir()
        try writeManifest(baseManifest(photos: [photo("photos/01.jpg", 0)]), to: bundle)
        try writePhotoFiles(["01.jpg", "02.jpg"], to: bundle)   // 02.jpg is a stray
        assertRejects(bundle, with: .unreferencedPhotoFile("photos/02.jpg"))
    }

    // MARK: - 6. order values not contiguous 0…n−1

    @Test func nonContiguousOrderIsRejected() throws {
        let bundle = try makeBundleDir()
        let photos = [photo("photos/01.jpg", 0), photo("photos/03.jpg", 2)]   // gap: no 1
        try writeManifest(baseManifest(photos: photos), to: bundle)
        try writePhotoFiles(["01.jpg", "03.jpg"], to: bundle)
        assertRejects(bundle, with: .nonContiguousOrder([0, 2]))
    }

    // MARK: - 7. duplicate order value

    @Test func duplicateOrderIsRejected() throws {
        let bundle = try makeBundleDir()
        let photos = [photo("photos/01.jpg", 0), photo("photos/02.jpg", 0)]   // both order 0
        try writeManifest(baseManifest(photos: photos), to: bundle)
        try writePhotoFiles(["01.jpg", "02.jpg"], to: bundle)
        assertRejects(bundle, with: .duplicateOrder(0))
    }

    // MARK: - 8. duplicate file reference

    @Test func duplicateFileReferenceIsRejected() throws {
        let bundle = try makeBundleDir()
        let photos = [photo("photos/01.jpg", 0), photo("photos/01.jpg", 1)]   // same file twice
        try writeManifest(baseManifest(photos: photos), to: bundle)
        try writePhotoFiles(["01.jpg"], to: bundle)
        assertRejects(bundle, with: .duplicateFileReference("photos/01.jpg"))
    }

    // MARK: - 9. more than 6 photos

    @Test func tooManyPhotosIsRejected() throws {
        let bundle = try makeBundleDir()
        let photos = (0..<7).map { photo(String(format: "photos/%02d.jpg", $0 + 1), $0) }
        try writeManifest(baseManifest(photos: photos), to: bundle)
        try writePhotoFiles((0..<7).map { String(format: "%02d.jpg", $0 + 1) }, to: bundle)
        assertRejects(bundle, with: .tooManyPhotos(7))
    }
}
