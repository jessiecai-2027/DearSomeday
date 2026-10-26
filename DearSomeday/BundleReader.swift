//
//  BundleReader.swift
//  DearSomeday
//
//  Read path for the §6.2 portable bundle. Inverse of `BundleWriter`.
//
//  ── §7.2: never partially import ──────────────────────────────────────────
//  `read` is one atomic operation: it returns a fully-loaded, fully-valid
//  `LoadedBundle`, or it throws — there is no public "parse then validate
//  later" seam a caller could forget. Every invariant below is checked before
//  any bytes are handed back; validation is built INTO the parse, not bolted on
//  after.
//
//  ── Filenames are read from the manifest, never derived ───────────────────
//  Each photo is loaded from its `PhotoRef.file` string exactly as written in
//  `manifest.json`. `order` is validated but never used to reconstruct a path —
//  the manifest is authoritative about which file backs which photo.
//
//  ── Why a wire layer ──────────────────────────────────────────────────────
//  The strict domain `ElementType` enum cannot represent an unknown value, so
//  decoding straight into it would surface a generic `DecodingError` that can't
//  be told apart from a dozen other malformed-JSON failures. Instead we decode
//  a permissive `Wire*` mirror (element `type` as a raw `String`), then map it
//  into the domain model — turning "unknown element type" into its own distinct
//  error at a place we control, while the domain types stay standalone.

import Foundation

enum BundleReadError: Error, Equatable {
    /// `manifest.json` absent, unreadable, or not decodable as our schema.
    case manifestMissingOrUnparseable
    /// `schemaVersion` present but not one this build understands.
    case unknownSchemaVersion(Int)
    /// A decoration element's `type` is not one of the known cases.
    case unknownElementType(String)
    /// A `PhotoRef.file` names a file that isn't in the bundle.
    case missingPhotoFile(String)
    /// A file exists under `photos/` that no `PhotoRef` references.
    case unreferencedPhotoFile(String)
    /// The `order` values are not exactly 0…n−1.
    case nonContiguousOrder([Int])
    /// Two photos share the same `order`.
    case duplicateOrder(Int)
    /// Two photos reference the same `file`.
    case duplicateFileReference(String)
    /// More than the creation maximum of 6 photos.
    case tooManyPhotos(Int)
}

/// A fully validated bundle. Photos are in manifest array order.
struct LoadedBundle: Equatable {
    var manifest: Manifest
    var photos: [LoadedPhoto]
}

struct LoadedPhoto: Equatable {
    /// The manifest entry that named this file — authoritative.
    var ref: PhotoRef
    var jpegData: Data
}

enum BundleReader {

    /// §5.1 photo cap. Zero photos (text-only cards) are permitted.
    static let maxPhotos = 6

    static func read(at bundleURL: URL) throws -> LoadedBundle {
        let fileManager = FileManager.default

        // 1. manifest.json — present, readable, parseable.
        let manifestURL = bundleURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw BundleReadError.manifestMissingOrUnparseable
        }

        // 2. schemaVersion first, so a future schema reports a version error
        //    rather than a confusing field-level decode failure from its body.
        guard let probe = try? JSONDecoder().decode(SchemaProbe.self, from: manifestData) else {
            throw BundleReadError.manifestMissingOrUnparseable
        }
        guard probe.schemaVersion == Manifest.latestSchemaVersion else {
            throw BundleReadError.unknownSchemaVersion(probe.schemaVersion)
        }

        // 3. Decode the permissive wire model. Any structural/type/date failure
        //    here (including a `draft`/unknown state, which is unrepresentable
        //    in a manifest by design) is a malformed manifest.
        guard let wire = try? Manifest.makeDecoder().decode(WireManifest.self, from: manifestData) else {
            throw BundleReadError.manifestMissingOrUnparseable
        }

        // 4. Map wire → domain, turning an unknown element type into its case.
        var elements: [DecorationElement] = []
        elements.reserveCapacity(wire.decoration.elements.count)
        for element in wire.decoration.elements {
            guard let type = ElementType(rawValue: element.type) else {
                throw BundleReadError.unknownElementType(element.type)
            }
            elements.append(DecorationElement(
                id: element.id,
                type: type,
                assetId: element.assetId,
                position: element.position,
                rotation: element.rotation,
                scale: element.scale,
                zIndex: element.zIndex,
                text: element.text,
                fontId: element.fontId
            ))
        }

        let manifest = Manifest(
            schemaVersion: wire.schemaVersion,
            id: wire.id,
            title: wire.title,
            description: wire.description,
            createdAt: wire.createdAt,
            editableUntil: wire.editableUntil,
            unlockDate: wire.unlockDate,
            state: wire.state,
            photos: wire.photos,
            decoration: Decoration(substrateId: wire.decoration.substrateId, elements: elements)
        )

        // 5. Structural checks that need no disk access.
        let orders = manifest.photos.map(\.order)
        let files = manifest.photos.map(\.file)

        guard manifest.photos.count <= maxPhotos else {
            throw BundleReadError.tooManyPhotos(manifest.photos.count)
        }
        if let dupOrder = firstDuplicate(orders) {
            throw BundleReadError.duplicateOrder(dupOrder)
        }
        if let dupFile = firstDuplicate(files) {
            throw BundleReadError.duplicateFileReference(dupFile)
        }
        // With no duplicates, contiguity ⇔ sorted orders == 0…n−1.
        if orders.sorted() != Array(0..<orders.count) {
            throw BundleReadError.nonContiguousOrder(orders)
        }

        // 6. Reconcile references against what's actually on disk.
        let photosDir = bundleURL.appendingPathComponent("photos", isDirectory: true)
        let referenced = Set(files)
        let onDisk = photoFilesOnDisk(in: photosDir, fileManager: fileManager)

        for file in files where !onDisk.contains(file) {
            throw BundleReadError.missingPhotoFile(file)
        }
        for file in onDisk.sorted() where !referenced.contains(file) {
            throw BundleReadError.unreferencedPhotoFile(file)
        }

        // 7. Everything valid — load bytes by the manifest's filenames, in order.
        var loaded: [LoadedPhoto] = []
        loaded.reserveCapacity(manifest.photos.count)
        for ref in manifest.photos {
            let fileURL = bundleURL.appendingPathComponent(ref.file, isDirectory: false)
            guard let data = try? Data(contentsOf: fileURL) else {
                throw BundleReadError.missingPhotoFile(ref.file)
            }
            loaded.append(LoadedPhoto(ref: ref, jpegData: data))
        }

        return LoadedBundle(manifest: manifest, photos: loaded)
    }

    // MARK: - Helpers

    /// Bundle-relative paths ("photos/NN.jpg") of the regular files under
    /// `photos/`. Hidden files (e.g. `.DS_Store`) are ignored so OS cruft
    /// doesn't read as an unreferenced photo. A missing directory yields the
    /// empty set — valid only if the manifest references no photos.
    private static func photoFilesOnDisk(in photosDir: URL, fileManager: FileManager) -> Set<String> {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: photosDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result: Set<String> = []
        for entry in entries {
            let isRegular = (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isRegular {
                result.insert("photos/\(entry.lastPathComponent)")
            }
        }
        return result
    }

    private static func firstDuplicate<T: Hashable>(_ values: [T]) -> T? {
        var seen = Set<T>()
        for value in values where !seen.insert(value).inserted {
            return value
        }
        return nil
    }
}

// MARK: - Wire model (permissive; reader-internal)

private struct SchemaProbe: Decodable {
    let schemaVersion: Int
}

private struct WireManifest: Decodable {
    let schemaVersion: Int
    let id: UUID
    let title: String
    let description: String
    let createdAt: Date
    let editableUntil: Date
    let unlockDate: Date
    let state: ManifestState
    let photos: [PhotoRef]
    let decoration: WireDecoration
}

private struct WireDecoration: Decodable {
    let substrateId: String
    let elements: [WireElement]
}

private struct WireElement: Decodable {
    let id: UUID
    /// Raw string so an unknown value is caught as `.unknownElementType`
    /// rather than a generic decode failure.
    let type: String
    let assetId: String
    let position: Position
    let rotation: Double
    let scale: Double
    let zIndex: Int
    let text: String?
    let fontId: String?
}
