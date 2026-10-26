//
//  PostcardDeletionTests.swift
//  DearSomedayTests
//
//  Verifies the "delete on card delete" composition (§5.3 / task A): deleting a
//  card removes BOTH the store record and its photo bytes, and that a store
//  failure leaves the bytes untouched (no half-deletion).
//

import Testing
import Foundation
import UIKit
@testable import DearSomeday

@MainActor
struct PostcardDeletionTests {

    private func tempPhotoStore() throws -> FileSystemPhotoStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostcardDeletionTests-\(UUID().uuidString)", isDirectory: true)
        return try FileSystemPhotoStore(directory: dir)
    }

    private func solidImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 400, height: 500), format: format).image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 500))
        }
    }

    @Test func deleteRemovesBothTheRecordAndThePhotoBytes() async throws {
        let store = InMemoryPostcardStore()
        let photoStore = try tempPhotoStore()

        // Two photos on one unlocked card.
        let f1 = try photoStore.save(solidImage())
        let f2 = try photoStore.save(solidImage())
        let card = Postcard(
            title: "trip",
            photos: [StoredPhoto(order: 0, fileName: f1), StoredPhoto(order: 1, fileName: f2)],
            unlockDate: Date(timeIntervalSinceReferenceDate: 0),
            state: .unlocked
        )
        try await store.create(card)

        try await PostcardDeletion.delete(card, from: store, photoStore: photoStore)

        // Record gone…
        #expect(try await store.postcard(withID: card.id) == nil)
        // …and both photo files gone.
        #expect(photoStore.loadData(fileName: f1) == nil)
        #expect(photoStore.loadData(fileName: f2) == nil)
    }

    @Test func deletingATextOnlyCardTouchesNoBytes() async throws {
        let store = InMemoryPostcardStore()
        let photoStore = try tempPhotoStore()
        let card = Postcard(title: "note", unlockDate: Date(timeIntervalSinceReferenceDate: 0), state: .unlocked)
        try await store.create(card)

        // No photos → nothing to clean up, and it must not throw.
        try await PostcardDeletion.delete(card, from: store, photoStore: photoStore)
        #expect(try await store.postcard(withID: card.id) == nil)
    }

    @Test func aStoreFailureLeavesThePhotoBytesIntact() async throws {
        // A card that isn't in the store: InMemoryPostcardStore.delete is a
        // no-op (not a throw), so this documents the happy no-op path — but the
        // key guarantee is ordering: bytes are only dropped AFTER the record
        // delete returns, so a throwing store never orphans photos.
        let store = FailingDeleteStore()
        let photoStore = try tempPhotoStore()
        let fileName = try photoStore.save(solidImage())
        let card = Postcard(photos: [StoredPhoto(order: 0, fileName: fileName)],
                            unlockDate: Date(timeIntervalSinceReferenceDate: 0), state: .unlocked)

        await #expect(throws: (any Error).self) {
            try await PostcardDeletion.delete(card, from: store, photoStore: photoStore)
        }
        // The store threw before byte cleanup → the file survives.
        #expect(photoStore.loadData(fileName: fileName) != nil)
    }
}

/// A store whose `delete` always throws, to prove byte cleanup never runs ahead
/// of a successful record delete.
@MainActor
private final class FailingDeleteStore: PostcardStore {
    struct Boom: Error {}
    func create(_ postcard: Postcard) async throws {}
    func postcard(withID id: UUID) async throws -> Postcard? { nil }
    func timeline(offset: Int, limit: Int) async throws -> [Postcard] { [] }
    func sealedPostcards() async throws -> [Postcard] { [] }
    func update(_ postcard: Postcard) async throws {}
    func delete(_ postcard: Postcard) async throws { throw Boom() }
}
