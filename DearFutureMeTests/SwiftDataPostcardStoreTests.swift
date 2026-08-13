//
//  SwiftDataPostcardStoreTests.swift
//  DearFutureMeTests
//
//  Exercises the production SwiftDataPostcardStore against the same
//  PostcardStore contract the in-memory double is tested against — over a real
//  (in-memory-backed) SwiftData container, so the SwiftData-specific behaviours
//  (predicate id lookup, managed-object identity, the foreign-instance update
//  path, enum filtering) are covered, not just the dictionary double.
//
//  Misuse paths (create() with a draft or duplicate id, update() of an absent
//  card) trip assertionFailure and so are not tested — same reasoning as the
//  in-memory suite.
//

import Testing
import Foundation
import SwiftData
@testable import DearFutureMe

@MainActor
struct SwiftDataPostcardStoreTests {

    // MARK: - Fixtures

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86_400

    /// A fresh ephemeral store per test — no disk, no cross-test bleed.
    private func makeStore() throws -> SwiftDataPostcardStore {
        let container = try SwiftDataPostcardStore.makeContainer(inMemory: true)
        return SwiftDataPostcardStore(container: container)
    }

    private func card(_ title: String, _ state: PostcardState, unlock: Date?) -> Postcard {
        Postcard(title: title, unlockDate: unlock, state: state)
    }

    // MARK: - Create + fetch

    @Test func createThenFetchReturnsTheSameManagedCard() async throws {
        let store = try makeStore()
        let pc = card("Iceland", .sealed, unlock: t0.addingTimeInterval(day))

        try await store.create(pc)
        let fetched = try await store.postcard(withID: pc.id)

        // SwiftData's identity map returns the very instance we inserted.
        #expect(fetched === pc)
        #expect(fetched?.title == "Iceland")
    }

    @Test func fetchMissingIDReturnsNil() async throws {
        let store = try makeStore()
        try await store.create(card("A", .sealed, unlock: t0))

        #expect(try await store.postcard(withID: UUID()) == nil)
    }

    @Test func createPersistsAcrossStoreInstancesOnTheSameContainer() async throws {
        // Two stores over one container see the same data — proves create()
        // actually saves, not just holds in a context.
        let container = try SwiftDataPostcardStore.makeContainer(inMemory: true)
        let writer = SwiftDataPostcardStore(container: container)
        let id = UUID()
        try await writer.create(Postcard(id: id, title: "kept", unlockDate: t0, state: .sealed))

        let reader = SwiftDataPostcardStore(container: container)
        #expect(try await reader.postcard(withID: id)?.title == "kept")
    }

    // MARK: - Update

    @Test func updatePersistsChangesToALiveObject() async throws {
        let store = try makeStore()
        let pc = card("sealed", .sealed, unlock: t0.addingTimeInterval(day))
        try await store.create(pc)

        pc.title = "opened"
        pc.state = .unlocked
        try await store.update(pc)

        let fetched = try await store.postcard(withID: pc.id)
        #expect(fetched?.title == "opened")
        #expect(fetched?.state == .unlocked)
    }

    @Test func updateWithAForeignInstanceCopiesItsValues() async throws {
        // A distinct instance carrying the same id updates the stored card's
        // VALUES. Unlike the in-memory double, SwiftData can't adopt the foreign
        // instance's identity (it isn't a managed object), so we assert values,
        // not `===` — which is all the protocol promises.
        let store = try makeStore()
        let id = UUID()
        try await store.create(Postcard(id: id, title: "first", unlockDate: t0, state: .sealed))

        let replacement = Postcard(id: id, title: "second", unlockDate: t0, state: .sealed)
        try await store.update(replacement)

        let fetched = try await store.postcard(withID: id)
        #expect(fetched?.title == "second")
        // Exactly one card under this id — the foreign instance wasn't inserted.
        #expect(try await store.timeline(offset: 0, limit: 50).filter { $0.id == id }.count == 1)
    }

    // MARK: - Delete

    @Test func deleteRemovesTheCard() async throws {
        let store = try makeStore()
        let pc = card("gone", .sealed, unlock: t0)
        try await store.create(pc)

        try await store.delete(pc)
        #expect(try await store.postcard(withID: pc.id) == nil)
    }

    @Test func deletingAnAbsentCardIsANoOp() async throws {
        let store = try makeStore()
        let present = card("kept", .sealed, unlock: t0)
        try await store.create(present)

        try await store.delete(card("never-stored", .sealed, unlock: t0))

        #expect(try await store.postcard(withID: present.id) != nil)
    }

    // MARK: - §5.5 ordering

    @Test func timelineOrdersSealedBySoonestThenUnlockedByMostRecent() async throws {
        let store = try makeStore()

        let sealedSoon = card("sealed-2d",  .sealed, unlock: t0.addingTimeInterval(2 * day))
        let sealedMid  = card("sealed-10d", .sealed, unlock: t0.addingTimeInterval(10 * day))
        let sealedFar  = card("sealed-30d", .sealed, unlock: t0.addingTimeInterval(30 * day))
        let unlockedRecent = card("unlocked-1d",  .unlocked, unlock: t0.addingTimeInterval(-1 * day))
        let unlockedMid    = card("unlocked-3d",  .unlocked, unlock: t0.addingTimeInterval(-3 * day))
        let unlockedOld    = card("unlocked-10d", .unlocked, unlock: t0.addingTimeInterval(-10 * day))

        for pc in [unlockedMid, sealedFar, unlockedOld, sealedSoon, unlockedRecent, sealedMid] {
            try await store.create(pc)
        }

        let titles = try await store.timeline(offset: 0, limit: 50).map(\.title)
        #expect(titles == [
            "sealed-2d", "sealed-10d", "sealed-30d",
            "unlocked-1d", "unlocked-3d", "unlocked-10d",
        ])
    }

    @Test func timelinePaginationSlicesTheGlobalOrder() async throws {
        let store = try makeStore()

        let sealedSoon = card("sealed-2d",  .sealed, unlock: t0.addingTimeInterval(2 * day))
        let sealedMid  = card("sealed-10d", .sealed, unlock: t0.addingTimeInterval(10 * day))
        let sealedFar  = card("sealed-30d", .sealed, unlock: t0.addingTimeInterval(30 * day))
        let unlocked   = card("unlocked-1d", .unlocked, unlock: t0.addingTimeInterval(-1 * day))
        for pc in [sealedFar, unlocked, sealedSoon, sealedMid] {
            try await store.create(pc)
        }

        let middle = try await store.timeline(offset: 1, limit: 2)
        #expect(middle.map(\.title) == ["sealed-10d", "sealed-30d"])

        #expect(try await store.timeline(offset: 10, limit: 50).isEmpty)
    }

    @Test func timelineExcludesADraftLeakedInByUpdate() async throws {
        // create() refuses drafts, but a defensive filter must also keep an
        // update-to-draft off the timeline (and out of the sealed set).
        let store = try makeStore()
        let pc = card("leaked", .sealed, unlock: t0.addingTimeInterval(day))
        try await store.create(pc)

        pc.state = .draft
        try await store.update(pc)

        #expect(try await store.timeline(offset: 0, limit: 50).isEmpty)
        #expect(try await store.sealedPostcards().isEmpty)
        // Still fetchable by id — it exists, it's just not on the timeline.
        #expect(try await store.postcard(withID: pc.id) != nil)
    }

    // MARK: - §5.7 sealed set

    @Test func sealedPostcardsReturnsOnlySealedCards() async throws {
        let store = try makeStore()
        let s1 = card("sealed-A", .sealed, unlock: t0.addingTimeInterval(day))
        let s2 = card("sealed-B", .sealed, unlock: t0.addingTimeInterval(5 * day))
        let u1 = card("unlocked", .unlocked, unlock: t0.addingTimeInterval(-day))
        for pc in [s1, u1, s2] { try await store.create(pc) }

        let sealed = try await store.sealedPostcards()
        #expect(Set(sealed.map(\.title)) == ["sealed-A", "sealed-B"])
    }

    @Test func sealedPostcardsIsEmptyWhenNoneSealed() async throws {
        let store = try makeStore()
        try await store.create(card("unlocked", .unlocked, unlock: t0.addingTimeInterval(-day)))

        #expect(try await store.sealedPostcards().isEmpty)
    }
}
