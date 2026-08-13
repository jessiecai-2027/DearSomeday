//
//  PhotoStore.swift
//  DearFutureMe
//
//  Local storage for postcard photo bytes — the layer Models.swift deferred
//  ("byte storage is a later layer"). `StoredPhoto.fileName` is a handle into
//  here.
//
//  ── What it stores (§6.1 + task-C decision) ────────────────────────────────
//  Display-resolution derivatives only — originals are NOT retained (§6.1).
//  Each imported image is:
//    1. auto center-cropped to 4:5 portrait (task-C decision — no crop UI in
//       the ugly loop, but data and display must already be correct),
//    2. downscaled so its longest edge ≤ 2048px (§6.1),
//    3. encoded JPEG at quality 0.8 (§6.1).
//
//  ── Where the bytes live ───────────────────────────────────────────────────
//  Application Support, NOT Caches: these derivatives are the only copy, so the
//  OS must never evict them. Application Support is included in device backups
//  by default, which is exactly what §3 relies on for restore-to-new-phone —
//  so it is deliberately NOT marked excluded-from-backup.
//
//  ── Scope ──────────────────────────────────────────────────────────────────
//  Byte I/O and the derivative pipeline only. It does not know about Postcard,
//  SwiftData, or the §6.2 bundle (that carries its own raw `Data`). Deleting a
//  card's photos "on card delete" is a caller composition — the delete-UX layer
//  calls `delete(fileNames:)` alongside `PostcardStore.delete`.
//

import Foundation
import UIKit

// MARK: - Protocol

protocol PhotoStore {

    /// Processes `image` into a 4:5 / ≤2048px / q0.8 JPEG derivative, writes it,
    /// and returns the opaque `fileName` handle to record on
    /// `StoredPhoto.fileName`. Throws if the image can't be processed or the
    /// write fails (e.g. storage full, §7.2).
    func save(_ image: UIImage) throws -> String

    /// The stored JPEG bytes for a handle, or nil if absent/unreadable.
    func loadData(fileName: String) -> Data?

    /// Deletes the bytes for each handle. A handle with no file is a silent
    /// no-op — deletion is idempotent, matching `PostcardStore.delete`.
    func delete(fileNames: [String])
}

enum PhotoStoreError: Error, Equatable {
    /// The source image had no decodable bitmap, or JPEG encoding failed.
    case unprocessableImage
}

// MARK: - Filesystem implementation

final class FileSystemPhotoStore: PhotoStore {

    private let directory: URL

    /// - Parameter directory: where derivatives are written. Created (with
    ///   intermediates) if absent. Injected so tests can use a temp dir.
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The production store: `Application Support/Photos`.
    static func applicationSupport(subdirectory: String = "Photos") throws -> FileSystemPhotoStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try FileSystemPhotoStore(directory: base.appendingPathComponent(subdirectory, isDirectory: true))
    }

    func save(_ image: UIImage) throws -> String {
        guard let data = PhotoProcessing.displayDerivative(from: image) else {
            throw PhotoStoreError.unprocessableImage
        }
        let fileName = UUID().uuidString + ".jpg"
        try data.write(to: url(for: fileName), options: .atomic)
        return fileName
    }

    func loadData(fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    func delete(fileNames: [String]) {
        for fileName in fileNames {
            try? FileManager.default.removeItem(at: url(for: fileName))
        }
    }

    private func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }
}

// MARK: - Derivative pipeline

/// The pure image transform behind `PhotoStore.save`: normalise orientation →
/// center-crop to 4:5 → downscale to ≤2048px → JPEG q0.8. Split out from the
/// filesystem store so the geometry is unit-testable without touching disk.
enum PhotoProcessing {

    /// Width ÷ height for 4:5 portrait.
    static let targetAspect: CGFloat = 4.0 / 5.0
    /// §6.1 longest-edge cap. For 4:5 portrait the height is the longest edge.
    static let maxLongestEdge: CGFloat = 2048
    /// §6.1 JPEG quality.
    static let jpegQuality: CGFloat = 0.8

    /// The full pipeline. Returns nil only if the image has no decodable bitmap
    /// or JPEG encoding fails — surfaced by the store as `.unprocessableImage`.
    static func displayDerivative(from image: UIImage) -> Data? {
        guard let normalized = normalizedCGImage(image) else { return nil }
        let cropped = centerCropToTargetAspect(normalized)
        let scaled = downscaleToCap(cropped)
        return UIImage(cgImage: scaled).jpegData(compressionQuality: jpegQuality)
    }

    /// A `.up`-oriented `CGImage` in true pixel dimensions. Camera Roll photos
    /// carry EXIF orientation; cropping the raw `cgImage` would crop the wrong
    /// axis, so we redraw through the orientation first when it isn't already up.
    static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, image.scale == 1, let cg = image.cgImage {
            return cg
        }
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
        return rendered.cgImage
    }

    /// Center-crops to exactly 4:5 by trimming the longer axis. A source already
    /// at 4:5 is returned untouched.
    static func centerCropToTargetAspect(_ cg: CGImage) -> CGImage {
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let aspect = width / height

        var cropWidth = width
        var cropHeight = height
        if aspect > targetAspect {              // too wide → trim width
            cropWidth = (height * targetAspect).rounded()
        } else if aspect < targetAspect {       // too tall → trim height
            cropHeight = (width / targetAspect).rounded()
        }

        let x = ((width - cropWidth) / 2).rounded(.down)
        let y = ((height - cropHeight) / 2).rounded(.down)
        let rect = CGRect(x: x, y: y,
                          width: min(cropWidth, width - x),
                          height: min(cropHeight, height - y))
        return cg.cropping(to: rect) ?? cg
    }

    /// Downscales so the longest edge is ≤ 2048px. Never upscales — a small
    /// source keeps its dimensions.
    static func downscaleToCap(_ cg: CGImage) -> CGImage {
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let longest = max(width, height)
        guard longest > maxLongestEdge else { return cg }

        let scale = maxLongestEdge / longest
        let targetSize = CGSize(width: (width * scale).rounded(),
                                height: (height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.cgImage ?? cg
    }
}
