//
//  PostcardTimelineSort.swift
//  DearSomeday
//
//  The single source of truth for the §5.5 timeline ordering, so every
//  `PostcardStore` conformer sorts identically. The SwiftData store sorts in
//  memory with it (the §5.5 order can't be expressed as one FetchDescriptor —
//  see below); the in-memory test double uses the exact same function, so a
//  test passing against the double proves the real store's ordering too.
//
//  ── Why not a FetchDescriptor sort ─────────────────────────────────────────
//  §5.5 is TWO groups with OPPOSITE directions: sealed by `unlockDate`
//  ascending (soonest unlock at the top), then unlocked by `unlockDate`
//  descending (most recently opened first). `FetchDescriptor.sortBy` applies
//  one uniform ordering to the whole result, so it cannot flip direction at the
//  group boundary, nor place nil-unlockDate sealed cards last. At v1 scale the
//  accepted trade (this task) is to fetch the non-draft cards and sort them
//  here in memory; revisit only if the 200-card perf target (§8) bites.
//

import Foundation

enum PostcardTimelineSort {

    /// A strict-weak, **total** ordering matching §5.5. Deterministic
    /// tiebreakers (`createdAt`, then `id`) make it total so offset pagination
    /// can't skip or duplicate rows when two cards would otherwise tie.
    ///
    /// Assumes drafts have already been filtered out — a draft has no defined
    /// slot in the §5.5 sort. Sealed cards are expected to carry a non-nil
    /// `unlockDate` (the §5.3 invariant the schema can't enforce); one that
    /// doesn't is sorted last within its group rather than crashing.
    static func precedes(_ a: Postcard, _ b: Postcard) -> Bool {
        // 1. Sealed cards precede unlocked cards.
        if (a.state == .sealed) != (b.state == .sealed) {
            return a.state == .sealed
        }

        // Sealed → unlockDate ascending; unlocked → descending.
        let ascending = (a.state == .sealed)

        // 2. By unlockDate, with nils sorted last within the group.
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
