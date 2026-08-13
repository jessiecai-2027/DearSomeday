//
//  PhotoStoreTests.swift
//  DearFutureMeTests
//
//  Covers the two halves of PhotoStore: the derivative geometry
//  (PhotoProcessing — 4:5 center-crop, ≤2048px longest edge, JPEG q0.8) and the
//  filesystem I/O (save → load round-trip, idempotent delete). Source images
//  are generated at known pixel sizes so the crop/scale maths is assertable
//  without shipping fixture files.
//

import Testing
import Foundation
import UIKit
@testable import DearFutureMe

@MainActor
struct PhotoStoreTests {

    // MARK: - Helpers

    /// A solid-colour image at an exact pixel size (scale 1, `.up` orientation).
    private func solidImage(width: Int, height: Int, color: UIColor = .systemTeal) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Decodes JPEG bytes back to pixel dimensions.
    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let image = try #require(UIImage(data: data))
        let cg = try #require(image.cgImage)
        return (cg.width, cg.height)
    }

    private func tempStore() throws -> FileSystemPhotoStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        return try FileSystemPhotoStore(directory: dir)
    }

    private let aspectTolerance = 0.01

    // MARK: - Geometry

    @Test func squareIsCroppedTo4x5AndCappedAt2048() throws {
        let data = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 3000, height: 3000)))
        let (w, h) = try pixelSize(of: data)

        // Portrait 4:5, longest edge (height) clamped to the cap.
        #expect(h == 2048)
        #expect(abs(Double(w) / Double(h) - 0.8) < aspectTolerance)
        #expect(max(w, h) <= 2048)
    }

    @Test func alreadyPortraitBelowCapKeepsItsDimensions() throws {
        // 400×500 is exactly 4:5 and under the cap — no crop, no scale, no upscale.
        let data = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 400, height: 500)))
        let (w, h) = try pixelSize(of: data)

        #expect(w == 400)
        #expect(h == 500)
    }

    @Test func wideImageIsCroppedToPortraitNotStretched() throws {
        // 3000×1000 → trim width to 4:5 (800×1000); height under the cap, no scale.
        let data = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 3000, height: 1000)))
        let (w, h) = try pixelSize(of: data)

        #expect(h == 1000)
        #expect(w == 800)
        #expect(abs(Double(w) / Double(h) - 0.8) < aspectTolerance)
    }

    @Test func tallImageAboveCapCropsThenDownscales() throws {
        // 1000×4000 → crop height to 4:5 (1000×1250), then cap height at 2048
        // (already under it → stays 1000×1250). Verifies crop-then-cap ordering.
        let data = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 1000, height: 4000)))
        let (w, h) = try pixelSize(of: data)

        #expect(max(w, h) <= 2048)
        #expect(abs(Double(w) / Double(h) - 0.8) < aspectTolerance)
    }

    @Test func derivativeIsJPEG() throws {
        let data = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 1200, height: 1500)))
        // JPEG SOI marker.
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }

    // MARK: - Filesystem round-trip

    @Test func saveReturnsAHandleThatLoadsBack() throws {
        let store = try tempStore()
        let handle = try store.save(solidImage(width: 1200, height: 1500))

        #expect(handle.hasSuffix(".jpg"))
        let loaded = try #require(store.loadData(fileName: handle))
        // What loads back decodes as a valid image at the derivative geometry.
        let (w, h) = try pixelSize(of: loaded)
        #expect(abs(Double(w) / Double(h) - 0.8) < aspectTolerance)
    }

    @Test func distinctSavesGetDistinctHandles() throws {
        let store = try tempStore()
        let a = try store.save(solidImage(width: 800, height: 1000))
        let b = try store.save(solidImage(width: 800, height: 1000))
        #expect(a != b)
    }

    @Test func loadingAnUnknownHandleReturnsNil() throws {
        let store = try tempStore()
        #expect(store.loadData(fileName: "nope.jpg") == nil)
    }

    // MARK: - Delete

    @Test func deleteRemovesTheBytes() throws {
        let store = try tempStore()
        let handle = try store.save(solidImage(width: 800, height: 1000))
        #expect(store.loadData(fileName: handle) != nil)

        store.delete(fileNames: [handle])
        #expect(store.loadData(fileName: handle) == nil)
    }

    @Test func deletingAMissingHandleIsANoOp() throws {
        let store = try tempStore()
        // Neither throws nor disturbs anything.
        store.delete(fileNames: ["never-written.jpg"])

        let kept = try store.save(solidImage(width: 800, height: 1000))
        store.delete(fileNames: ["still-missing.jpg"])
        #expect(store.loadData(fileName: kept) != nil)
    }
}
