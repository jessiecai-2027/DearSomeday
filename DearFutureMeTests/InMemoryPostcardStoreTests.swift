//
//  InMemoryPostcardStoreTests.swift
//  DearFutureMeTests
//
//  Exercises the InMemoryPostcardStore against the PostcardStore contract:
//  create, fetch, update, delete, and the §5.5 timeline ordering over a mix of
//  sealed and unlocked cards.
//
//  The misuse paths (create() with a draft or a duplicate id, update() of an
//  absent card) are deliberately NOT tested here — they trip assertionFailure,
//  which traps in a debug test build. They're contract preconditions, not
//  recoverable behaviour, so there's nothing to assert.
//

import Testing
import Foundation
@testable import DearFutureMe

@MainActor
struct InMemoryPostcardStoreTests {

    // MARK: - Fixtures

    /// A fixed reference instant so unlock-date arithmetic is deterministic.
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86_400

    private func card(
        _ title: String,
        _ state: PostcardState,
        unlock: Date?
    ) -> Postcard {
        Postcard(title: title, unlockDate: unlock, state: state)
    }

    // MARK: - Create + fetch

    @Test func createThenFetchReturnsTheSameCard() async throws {
        let store = InMemoryPostcardStore()
        let pc = card("Iceland", .sealed, unlock: t0.addingTimeInterval(day))

        try await store.create(pc)
        let fetched = try await store.postcard(withID: pc.id)

        // Same identity, not just an equal copy (reference semantics).
        #expect(fetched === pc)
        #expect(fetched?.title == "Iceland")
    }

    @Test func fetchMissingIDReturnsNil() async throws {
        let store = InMemoryPostcardStore()
        try await store.create(card("A", .sealed, unlock: t0))

        let missing = try await store.postcard(withID: UUID())
        #expect(missing == nil)
    }

    // MARK: - Update

    @Test func updatePersistsChanges() async throws {
        let store = InMemoryPostcardStore()
        let pc = card("draft-of-a-card", .sealed, unlock: t0.addingTimeInterval(day))
        try await store.create(pc)

        // Seal window elapses, card unlocks: mutate and persist.
        pc.title = "opened"
        pc.state = .unlocked
        try await store.update(pc)

        let fetched = try await store.postcard(withID: pc.id)
        #expect(fetched?.title == "opened")
        #expect(fetched?.state == .unlocked)
    }

    @Test func updateWithAReplacementInstanceTakesEffect() async throws {
        let store = InMemoryPostcardStore()
        let id = UUID()
        try await store.create(Postcard(id: id, title: "first", unlockDate: t0, state: .sealed))

        // A distinct instance carrying the same id should replace the stored one.
        let replacement = Postcard(id: id, title: "second", unlockDate: t0, state: .sealed)
        try await store.update(replacement)

        let fetched = try await store.postcard(withID: id)
        #expect(fetched === replacement)
        #expect(fetched?.title == "second")
    }

    // MARK: - Delete

    @Test func deleteRemovesTheCard() async throws {
        let store = InMemoryPostcardStore()
        let pc = card("gone", .sealed, unlock: t0)
        try await store.create(pc)

        try await store.delete(pc)
        #expect(try await store.postcard(withID: pc.id) == nil)
    }

    @Test func deletingAnAbsentCardIsANoOp() async throws {
        let store = InMemoryPostcardStore()
        let present = card("kept", .sealed, unlock: t0)
        try await store.create(present)

        // Never stored — must not throw or disturb existing state.
        try await store.delete(card("never-stored", .sealed, unlock: t0))

        #expect(try await store.postcard(withID: present.id) != nil)
    }

    // MARK: - §5.5 ordering (mixed sealed + unlocked)

    @Test func timelineOrdersSealedBySoonestThenUnlockedByMostRecent() async throws {
        let store = InMemoryPostcardStore()

        // Sealed: ordered by unlockDate ASCENDING (soonest unlock at the top).
        let sealedSoon = card("sealed-2d",  .sealed, unlock: t0.addingTimeInterval(2 * day))
        let sealedMid  = card("sealed-10d", .sealed, unlock: t0.addingTimeInterval(10 * day))
        let sealedFar  = card("sealed-30d", .sealed, unlock: t0.addingTimeInterval(30 * day))

        // Unlocked: ordered by unlockDate DESCENDING (most recently opened first).
        let unlockedRecent = card("unlocked-1d",  .unlocked, unlock: t0.addingTimeInterval(-1 * day))
        let unlockedMid    = card("unlocked-3d",  .unlocked, unlock: t0.addingTimeInterval(-3 * day))
        let unlockedOld    = card("unlocked-10d", .unlocked, unlock: t0.addingTimeInterval(-10 * day))

        // Insert deliberately scrambled so a passing test means real sorting,
        // not insertion order leaking through.
        for pc in [unlockedMid, sealedFar, unlockedOld, sealedSoon, unlockedRecent, sealedMid] {
            try await store.create(pc)
        }

        let page = try await store.timeline(offset: 0, limit: 50)
        let titles = page.map(\.title)

        #expect(titles == [
            "sealed-2d", "sealed-10d", "sealed-30d",   // sealed, soonest → furthest
            "unlocked-1d", "unlocked-3d", "unlocked-10d", // unlocked, most recent → oldest
        ])
    }

    @Test func timelinePaginationSlicesTheGlobalOrder() async throws {
        let store = InMemoryPostcardStore()

        let sealedSoon = card("sealed-2d",  .sealed, unlock: t0.addingTimeInterval(2 * day))
        let sealedMid  = card("sealed-10d", .sealed, unlock: t0.addingTimeInterval(10 * day))
        let sealedFar  = card("sealed-30d", .sealed, unlock: t0.addingTimeInterval(30 * day))
        let unlocked   = card("unlocked-1d", .unlocked, unlock: t0.addingTimeInterval(-1 * day))
        for pc in [sealedFar, unlocked, sealedSoon, sealedMid] {
            try await store.create(pc)
        }

        // Full order is [sealed-2d, sealed-10d, sealed-30d, unlocked-1d].
        let middle = try await store.timeline(offset: 1, limit: 2)
        #expect(middle.map(\.title) == ["sealed-10d", "sealed-30d"])

        // Past-the-end offset yields an empty page, not a crash.
        let tail = try await store.timeline(offset: 10, limit: 50)
        #expect(tail.isEmpty)
    }
}
