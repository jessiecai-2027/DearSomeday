//
//  PhotoStoreTests.swift
//  DearSomedayTests
//
//  Covers the two halves of PhotoStore: the derivative geometry
//  (PhotoProcessing — aspect-preserving, ≤2048px longest edge, JPEG q0.8) and the
//  filesystem I/O (save → load round-trip, idempotent delete). Source images
//  are generated at known pixel sizes so the crop/scale maths is assertable
//  without shipping fixture files.
//

import Testing
import Foundation
import UIKit
@testable import DearSomeday

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

    @Test func squareIsPreservedAndCappedAt2048() throws {
        let output = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 3000, height: 3000)))
        let (w, h) = try pixelSize(of: output.jpegData)

        #expect(w == 2048)
        #expect(h == 2048)
        #expect(max(w, h) <= 2048)
        #expect(output.pixelWidth == w)
        #expect(output.pixelHeight == h)
    }

    @Test func portraitBelowCapKeepsItsDimensions() throws {
        let output = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 400, height: 500)))
        let (w, h) = try pixelSize(of: output.jpegData)

        #expect(w == 400)
        #expect(h == 500)
    }

    @Test func wideImageKeepsAspectAndCapsLongestEdge() throws {
        let output = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 3000, height: 1000)))
        let (w, h) = try pixelSize(of: output.jpegData)

        #expect(w == 2048)
        #expect(abs(Double(w) / Double(h) - 3.0) < aspectTolerance)
        #expect(max(w, h) <= 2048)
    }

    @Test func tallImageKeepsAspectAndCapsLongestEdge() throws {
        let output = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 1000, height: 4000)))
        let (w, h) = try pixelSize(of: output.jpegData)

        #expect(h == 2048)
        #expect(max(w, h) <= 2048)
        #expect(abs(Double(w) / Double(h) - 0.25) < aspectTolerance)
    }

    @Test func derivativeIsJPEG() throws {
        let output = try #require(PhotoProcessing.displayDerivative(from: solidImage(width: 1200, height: 1500)))
        // JPEG SOI marker.
        #expect(output.jpegData.prefix(2) == Data([0xFF, 0xD8]))
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

    @Test func saveDerivativeReturnsGeometryMetadata() throws {
        let store = try tempStore()
        let saved = try store.saveDerivative(solidImage(width: 1600, height: 900))

        #expect(saved.fileName.hasSuffix(".jpg"))
        #expect(saved.pixelWidth == 1600)
        #expect(saved.pixelHeight == 900)
        #expect(abs(Double(saved.aspect) - (16.0 / 9.0)) < aspectTolerance)
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
