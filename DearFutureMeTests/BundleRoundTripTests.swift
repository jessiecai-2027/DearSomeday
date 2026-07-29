//
//  BundleRoundTripTests.swift
//  DearFutureMeTests
//
//  Round-trip tests for the §6.2 bundle format. Everything goes through a real
//  temp directory on disk — write with BundleWriter, read back with
//  BundleReader — never encode/decode against an in-memory Data blob.
//

import Testing
import Foundation
@testable import DearFutureMe

struct BundleRoundTripTests {

    // MARK: - Fixtures

    /// Whole-second timestamps, so `.iso8601` round-trips them exactly and full
    /// `Manifest` equality is meaningful.
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dfm-bundle-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Distinct bytes per photo so a mix-up in ordering is caught.
    private func photoData(_ index: Int) -> Data {
        Data([0xFF, 0xD8, UInt8(index & 0xFF), 0x42, 0xFF, 0xD9])
    }

    private func element(
        id: UUID = UUID(),
        type: ElementType,
        x: Double, y: Double,
        rotation: Double, scale: Double, zIndex: Int,
        text: String? = nil, fontId: String? = nil
    ) -> DecorationElement {
        DecorationElement(
            id: id, type: type, assetId: "asset-\(zIndex)",
            position: Position(x: x, y: y),
            rotation: rotation, scale: scale, zIndex: zIndex,
            text: text, fontId: fontId
        )
    }

    // MARK: - 1. Fully populated card

    @Test func fullyPopulatedCardRoundTrips() throws {
        let dir = try makeTempDirectory()

        let e1 = element(type: .sticker,   x: 0.42, y: 0.18, rotation: -2.5, scale: 1.00, zIndex: 3)
        let e2 = element(type: .tape,      x: 0.10, y: 0.90, rotation: 12.0, scale: 0.75, zIndex: 1)
        let e3 = element(type: .text,      x: 0.50, y: 0.50, rotation: 0.0,  scale: 1.25, zIndex: 7,
                         text: "see you", fontId: "serif-01")

        let manifest = Manifest(
            id: UUID(),
            title: "Iceland",
            description: "Ring road, day nine.",
            createdAt: t0,
            editableUntil: t0.addingTimeInterval(3600),
            unlockDate: t0.addingTimeInterval(86_400),
            state: .sealed,
            photos: [
                PhotoRef(file: "photos/01.jpg", order: 0),
                PhotoRef(file: "photos/02.jpg", order: 1),
                PhotoRef(file: "photos/03.jpg", order: 2),
            ],
            decoration: Decoration(substrateId: "kraft-01", elements: [e1, e2, e3])
        )
        let bundlePhotos = (0..<3).map { BundlePhoto(order: $0, jpegData: photoData($0)) }

        let bundleURL = try BundleWriter.write(manifest, photos: bundlePhotos, to: dir)
        let loaded = try BundleReader.read(at: bundleURL)

        // Photo order preserved.
        #expect(loaded.photos.map(\.ref.order) == [0, 1, 2])

        // Photo bytes match, keyed by order.
        for photo in loaded.photos {
            #expect(photo.jpegData == photoData(photo.ref.order))
        }

        // Every element's geometry survives.
        #expect(loaded.manifest.decoration.elements.count == 3)
        for original in [e1, e2, e3] {
            let round = try #require(
                loaded.manifest.decoration.elements.first { $0.id == original.id }
            )
            #expect(round.position == original.position)
            #expect(round.rotation == original.rotation)
            #expect(round.scale == original.scale)
            #expect(round.zIndex == original.zIndex)
        }

        // Strong check: the whole manifest is identical after the trip.
        #expect(loaded.manifest == manifest)
    }

    // MARK: - 2. Empty card (§5.1 permits empty title/description/zero photos)

    @Test func emptyCardRoundTrips() throws {
        let dir = try makeTempDirectory()

        let manifest = Manifest(
            id: UUID(),
            title: "",
            description: "",
            createdAt: t0,
            editableUntil: t0,
            unlockDate: t0,
            state: .sealed,
            photos: [],
            decoration: Decoration(substrateId: "kraft-01", elements: [])
        )

        let bundleURL = try BundleWriter.write(manifest, photos: [], to: dir)
        let loaded = try BundleReader.read(at: bundleURL)

        #expect(loaded.manifest.title == "")
        #expect(loaded.manifest.description == "")
        #expect(loaded.photos.isEmpty)
        #expect(loaded.manifest.decoration.elements.isEmpty)
        #expect(loaded.manifest == manifest)
    }

    // MARK: - 3. Exactly 10 photos — the §5.1 boundary

    @Test func tenPhotosIsValid() throws {
        let dir = try makeTempDirectory()

        let photos = (0..<10).map {
            PhotoRef(file: String(format: "photos/%02d.jpg", $0 + 1), order: $0)
        }
        let manifest = Manifest(
            id: UUID(),
            title: "Ten",
            description: "",
            createdAt: t0,
            editableUntil: t0,
            unlockDate: t0,
            state: .unlocked,
            photos: photos,
            decoration: Decoration(substrateId: "kraft-01", elements: [])
        )
        let bundlePhotos = (0..<10).map { BundlePhoto(order: $0, jpegData: photoData($0)) }

        let bundleURL = try BundleWriter.write(manifest, photos: bundlePhotos, to: dir)
        let loaded = try BundleReader.read(at: bundleURL)

        #expect(loaded.photos.count == 10)
        #expect(loaded.photos.map(\.ref.order) == Array(0..<10))
        for photo in loaded.photos {
            #expect(photo.jpegData == photoData(photo.ref.order))
        }
    }

    // MARK: - 4. .DS_Store in photos/ is ignored (hidden-file skip is deliberate)

    @Test func hiddenFileInPhotosDirIsIgnored() throws {
        let dir = try makeTempDirectory()

        let manifest = Manifest(
            id: UUID(),
            title: "Cruft",
            description: "",
            createdAt: t0,
            editableUntil: t0,
            unlockDate: t0,
            state: .sealed,
            photos: [
                PhotoRef(file: "photos/01.jpg", order: 0),
                PhotoRef(file: "photos/02.jpg", order: 1),
            ],
            decoration: Decoration(substrateId: "kraft-01", elements: [])
        )
        let bundlePhotos = (0..<2).map { BundlePhoto(order: $0, jpegData: photoData($0)) }

        let bundleURL = try BundleWriter.write(manifest, photos: bundlePhotos, to: dir)

        // Drop OS cruft alongside the real photos.
        let dsStore = bundleURL.appendingPathComponent("photos/.DS_Store", isDirectory: false)
        try Data([0x00, 0x01, 0x02]).write(to: dsStore)

        // Must still read cleanly — the hidden-file skip is intentional, not luck.
        let loaded = try BundleReader.read(at: bundleURL)
        #expect(loaded.photos.count == 2)
        #expect(loaded.photos.map(\.ref.order) == [0, 1])
        for photo in loaded.photos {
            #expect(photo.jpegData == photoData(photo.ref.order))
        }
    }
}
