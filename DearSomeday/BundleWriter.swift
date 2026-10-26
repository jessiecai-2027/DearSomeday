//
//  BundleWriter.swift
//  DearSomeday
//
//  Write path for the §6.2 portable bundle. Given a `Manifest` plus the JPEG
//  bytes for its photos, produces:
//
//      postcard-<uuid>.bundle/
//      ├── manifest.json
//      └── photos/01.jpg, 02.jpg, …
//
//  Write only — no decoding, no import, no round-trip. The reader is a later
//  task.
//
//  ── Filenames come from the manifest's `order` field ──────────────────────
//  §6.2's example pairs `"order": 0` with `"file": "photos/01.jpg"`, so the
//  on-disk photo number is `order + 1`, zero-padded. The writer is the single
//  authority on those names: it sorts the photos by `order`, derives the
//  canonical `photos/NN.jpg` path from `order`, writes the bytes there, AND
//  rewrites each `PhotoRef.file` to that same path before encoding
//  `manifest.json`. The manifest and the files therefore cannot disagree.
//
//  ── Atomicity ─────────────────────────────────────────────────────────────
//  The bundle is assembled in a sibling temp directory and moved into place in
//  one step, so a failure part-way through never leaves a half-written
//  `.bundle` at the destination (cf. §7.2 "never partially import" — the write
//  side of the same trust contract).

import Foundation

enum BundleWriteError: Error, Equatable {
    /// A photo referenced by the manifest had no bytes supplied.
    case missingPhotoData(order: Int)
    /// Bytes were supplied for an `order` the manifest doesn't reference.
    case unexpectedPhotoData(order: Int)
    /// Two photos share the same `order`; filenames would collide.
    case duplicateOrder(Int)
}

/// JPEG bytes for one photo, paired with the `order` that ties it to a
/// `PhotoRef` in the manifest.
struct BundlePhoto: Equatable {
    var order: Int
    var jpegData: Data
}

enum BundleWriter {

    /// Writes `manifest` and `photos` as a `postcard-<uuid>.bundle` directory
    /// inside `destinationDirectory`. Returns the bundle's URL.
    ///
    /// An existing bundle with the same UUID is replaced.
    @discardableResult
    static func write(
        _ manifest: Manifest,
        photos: [BundlePhoto],
        to destinationDirectory: URL
    ) throws -> URL {

        let fileManager = FileManager.default

        // 1. Reconcile supplied bytes against the manifest by `order`.
        var dataByOrder: [Int: Data] = [:]
        for photo in photos {
            guard dataByOrder[photo.order] == nil else {
                throw BundleWriteError.duplicateOrder(photo.order)
            }
            dataByOrder[photo.order] = photo.jpegData
        }

        let manifestOrders = manifest.photos.map(\.order)
        for order in manifestOrders where dataByOrder[order] == nil {
            throw BundleWriteError.missingPhotoData(order: order)
        }
        let manifestOrderSet = Set(manifestOrders)
        for order in dataByOrder.keys where !manifestOrderSet.contains(order) {
            throw BundleWriteError.unexpectedPhotoData(order: order)
        }
        if manifestOrderSet.count != manifestOrders.count {
            // Duplicate order inside the manifest itself.
            var seen = Set<Int>()
            let dup = manifestOrders.first { !seen.insert($0).inserted } ?? 0
            throw BundleWriteError.duplicateOrder(dup)
        }

        // 2. Canonicalise: sort by order, derive zero-padded filenames from it.
        let sorted = manifest.photos.sorted { $0.order < $1.order }
        let width = filenameWidth(for: manifestOrders)

        var canonical = manifest
        canonical.photos = sorted.map {
            PhotoRef(file: photoPath(order: $0.order, width: width), order: $0.order)
        }

        // 3. Assemble in a sibling temp dir, then move into place atomically.
        let bundleURL = destinationDirectory
            .appendingPathComponent("postcard-\(manifest.id.uuidString.lowercased()).bundle",
                                    isDirectory: true)
        let tempURL = destinationDirectory
            .appendingPathComponent(".postcard-\(manifest.id.uuidString.lowercased())"
                                    + ".\(ProcessInfo.processInfo.globallyUniqueString).tmp",
                                    isDirectory: true)

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)

        do {
            let photosDir = tempURL.appendingPathComponent("photos", isDirectory: true)
            try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)

            for ref in canonical.photos {
                // `ref.file` is "photos/NN.jpg"; write the bytes there.
                let fileURL = tempURL.appendingPathComponent(ref.file, isDirectory: false)
                try dataByOrder[ref.order]!.write(to: fileURL, options: .atomic)
            }

            let encoder = Manifest.makeEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let manifestData = try encoder.encode(canonical)
            try manifestData.write(to: tempURL.appendingPathComponent("manifest.json"),
                                   options: .atomic)

            // Swap into place.
            if fileManager.fileExists(atPath: bundleURL.path) {
                try fileManager.removeItem(at: bundleURL)
            }
            try fileManager.moveItem(at: tempURL, to: bundleURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }

        return bundleURL
    }

    // MARK: - Filenames

    /// Number of digits to zero-pad to. At least 2 (matching §6.2's "01.jpg"),
    /// wider only if a photo's number would overflow it.
    private static func filenameWidth(for orders: [Int]) -> Int {
        let maxNumber = (orders.max() ?? 0) + 1
        return max(2, String(maxNumber).count)
    }

    private static func photoPath(order: Int, width: Int) -> String {
        "photos/\(zeroPadded(order + 1, width: width)).jpg"
    }

    private static func zeroPadded(_ n: Int, width: Int) -> String {
        let digits = String(n)
        guard digits.count < width else { return digits }
        return String(repeating: "0", count: width - digits.count) + digits
    }
}
