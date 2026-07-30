//
//  InMemoryPostcardStore.swift
//  DearFutureMeTests
//
//  A `PostcardStore` conformer backed by a dictionary — no SwiftData, no disk.
//  Test infrastructure only; it lives in the test target so it never ships.
//
//  It is a *faithful* double, not a stub: it enforces the same contract the
//  real SwiftData store must (§5.5 ordering, the draft precondition, the id
//  uniqueness invariant), so a test passing against this store is exercising
//  the actual rules — not a permissive fake that hides them.
//
//  Reference semantics note: `Postcard` is a class, so the instances handed to
//  `create`/`update` are stored by reference and returned by reference. A test
//  that mutates a card it fetched is mutating the "persisted" one too — the
//  same as SwiftData's live-object behaviour, so tests port cleanly.
//

import Foundation
@testable import DearFutureMe

@MainActor
final class InMemoryPostcardStore: PostcardStore {

    /// Keyed by the domain `id` (§6.1). Keying by `id` is what makes the
    /// uniqueness invariant observable here, since the schema can't enforce it.
    private var storage: [UUID: Postcard] = [:]

    // MARK: - Create

    func create(_ postcard: Postcard) async throws {
        // Precondition: drafts never persist (§7.2). Caller misuse, not an
        // operational error — assert in debug, no-op in release.
        guard postcard.state != .draft else {
            assertionFailure("create() was passed a draft; drafts live in the composer, not the store")
            return
        }
        // Uniqueness invariant (§3 forbids a store-level unique constraint):
        // don't silently store a second copy under a colliding id.
        guard storage[postcard.id] == nil else {
            assertionFailure("create() was passed a duplicate id \(postcard.id)")
            return
        }
        storage[postcard.id] = postcard
    }

    // MARK: - Fetch (single)

    func postcard(withID id: UUID) async throws -> Postcard? {
        storage[id]
    }

    // MARK: - Fetch (timeline, ordered + paginated — §5.5)

    func timeline(offset: Int, limit: Int) async throws -> [Postcard] {
        // Drafts are excluded from the timeline; create() already keeps them
        // out of storage, but filter defensively so an update-to-draft can't
        // leak one in.
        let visible = storage.values.filter { $0.state != .draft }
        let ordered = visible.sorted(by: Self.timelineOrder)

        // Crash-safe slice for any offset/limit, including out-of-range or
        // negative values (which are misuse, but shouldn't trap).
        let start = min(max(0, offset), ordered.count)
        let end = min(start + max(0, limit), ordered.count)
        return Array(ordered[start..<end])
    }

    // MARK: - Update

    func update(_ postcard: Postcard) async throws {
        // Update targets an existing card; updating an absent one is misuse.
        guard storage[postcard.id] != nil else {
            assertionFailure("update() was passed a postcard that isn't stored: \(postcard.id)")
            return
        }
        storage[postcard.id] = postcard
    }

    // MARK: - Delete

    func delete(_ postcard: Postcard) async throws {
        // "Deleting a card that is not present is a no-op, not an error."
        storage[postcard.id] = nil
    }

    // MARK: - §5.5 ordering

    /// Total order matching §5.5: sealed group first (soonest unlock at top),
    /// then unlocked group (most recent first). Deterministic tiebreakers make
    /// it a *total* order so offset pagination can't skip or duplicate rows.
    private static func timelineOrder(_ a: Postcard, _ b: Postcard) -> Bool {
        // 1. Sealed cards precede unlocked cards.
        if (a.state == .sealed) != (b.state == .sealed) {
            return a.state == .sealed
        }

        // Sealed → unlockDate ascending; unlocked → descending.
        let ascending = (a.state == .sealed)

        // 2. By unlockDate, with nils sorted last within the group. (A sealed
        //    card with a nil unlockDate violates the §5.3 invariant the schema
        //    can't enforce; we sort it last rather than crash.)
        switch (a.unlockDate, b.unlockDate) {
        case let (ua?, ub?) where ua != ub:
            return ascending ? (ua < ub) : (ua > ub)
        case (nil, .some):
            return false            // a (nil) sorts after b
        case (.some, nil):
            return true             // a sorts before b (nil)
        default:
            break                   // both nil, or equal instants → tiebreak
        }

        // 3. Tiebreakers for a total order: createdAt (same direction as the
        //    group), then id as the final deterministic key.
        if a.createdAt != b.createdAt {
            return ascending ? (a.createdAt < b.createdAt) : (a.createdAt > b.createdAt)
        }
        return a.id.uuidString < b.id.uuidString
    }
}
