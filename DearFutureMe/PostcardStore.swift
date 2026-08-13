//
//  PostcardStore.swift
//  DearFutureMe
//
//  The persistence seam (§3). All storage lives behind this protocol so that
//  Phase 2's CloudKit sync is an *implementation swap*, not a schema/API
//  migration. v1 ships one SwiftData conformer; tests get an in-memory one;
//  v1.1 adds a CloudKit-backed one — none of which change this file.
//
//  Scope of this file: PROTOCOL ONLY. No conformers, no SwiftData, no fetch
//  descriptors. Just the contract over the §6.1 models.
//
//  ── Deliberate shape decisions ─────────────────────────────────────────────
//
//  • `@MainActor`. The §6.1 models are MainActor-isolated (the module builds
//    with `-default-isolation=MainActor`) and non-Sendable, so any code holding
//    a `Postcard` is main-actor bound anyway. Stating it on the protocol makes
//    that explicit and keeps `Postcard` values from illegally crossing actor
//    boundaries.
//
//  • `async throws`. Local SwiftData reads are synchronous, so async buys
//    nothing *today* — it's for Phase 2. A CloudKit-backed conformer can
//    `await` network work and suspend the main actor (keeping the UI live)
//    without changing a single signature here. Making the methods async now is
//    what lets Phase 2 stay a pure implementation swap; retrofitting async
//    later would ripple through every call site — exactly the migration §3
//    tells us to avoid. A synchronous conformer simply never suspends.
//    `throws` is untyped so each backend surfaces its own errors (SwiftData,
//    CloudKit, storage-full §7.2) without a lowest-common-denominator enum.
//
//  • No `import SwiftData`. The contract references only `Postcard` and `UUID`,
//    so an in-memory test double or a CloudKit-direct backend satisfies it
//    without pulling in SwiftData. Storage-agnostic on purpose.
//
//  ── Invariants this protocol relies on but cannot enforce ──────────────────
//  `Postcard.id` is NOT unique at the store level (§3 forbids unique
//  constraints — see Models.swift). Uniqueness is an application invariant:
//  `create` is where a conformer must reject or dedupe a colliding id, and
//  `postcard(withID:)` assumes at most one match. The type system won't help.
//
//  ── §5.7 unpaginated sealed fetch ──────────────────────────────────────────
//  §5.7 ("re-scan all sealed cards and re-schedule on every launch") needs
//  every sealed card, not a 50-item timeline page — and the launch/foreground
//  unlock sweep (§5.4) needs the same set. `sealedPostcards()` provides it. It
//  was deferred in an earlier pass; the ugly core loop pulls §5.7 into scope,
//  so it lives here now.

import Foundation

@MainActor
protocol PostcardStore {

    // MARK: - Create

    /// Persists a new sealed or unlocked postcard.
    ///
    /// - Precondition: `postcard.state != .draft`. Drafts live only in the
    ///   composer's memory and reach the store at seal (§7.2); a persisted
    ///   draft would be unreachable — `timeline` hides it and there is no
    ///   drafts fetch — so it must never be stored. Passing one is caller
    ///   misuse, not an operational failure, so it is deliberately NOT on the
    ///   `throws` channel: conformers `assertionFailure` in debug and fail
    ///   gracefully in release (ignore the call, persist nothing).
    ///
    /// Because `id` is not store-unique, a conformer must also enforce the
    /// uniqueness invariant here — reject or dedupe a colliding `id` rather
    /// than silently storing a second copy. A duplicate `id` is likewise
    /// caller misuse (assert in debug, no-op in release), not a thrown error.
    ///
    /// - Throws: if the write itself fails (e.g. device storage full, §7.2).
    func create(_ postcard: Postcard) async throws

    // MARK: - Fetch (single)

    /// Returns the postcard with the given domain `id` (§6.1's own UUID, never
    /// `persistentModelID`), or `nil` if none exists.
    ///
    /// Serves draft resume and deep-links by id; the timeline uses
    /// `timeline(offset:limit:)` instead. Assumes at most one match per the
    /// uniqueness invariant above.
    func postcard(withID id: UUID) async throws -> Postcard?

    // MARK: - Fetch (timeline, ordered + paginated — §5.5)

    /// Returns one page of the timeline in the exact §5.5 order:
    ///
    ///   1. **Sealed cards first**, soonest unlock at the top — `unlockDate`
    ///      ascending.
    ///   2. **Unlocked cards below**, most recent first — `unlockDate`
    ///      descending.
    ///
    /// **Drafts are excluded.** §5.5 only positions sealed and unlocked cards;
    /// a draft is an in-progress compose resumed via `postcard(withID:)`, not a
    /// timeline row, and it has no defined slot in the sort.
    ///
    /// The order must be a **total order** — conformers append deterministic
    /// tiebreakers (e.g. `createdAt`, then `id`) within each group. Offset
    /// pagination silently skips or duplicates rows if two cards can tie, so
    /// stability is a correctness requirement, not a nicety.
    ///
    /// Sealed cards are expected to carry a non-nil `unlockDate` (the §5.3
    /// lifecycle invariant, which the schema can't enforce — see Models.swift);
    /// how a conformer orders a sealed card that violates this is left to the
    /// conformer, but it should not crash on it.
    ///
    /// - Parameters:
    ///   - offset: number of leading items to skip (0 for the first page).
    ///   - limit: maximum items to return. §5.5 loads in batches of 50; the
    ///     caller passes that batch size (protocol requirements can't declare
    ///     default arguments, so it isn't defaulted here).
    /// - Returns: up to `limit` postcards in timeline order; fewer at the end.
    func timeline(offset: Int, limit: Int) async throws -> [Postcard]

    // MARK: - Fetch (all sealed — §5.7)

    /// Every card currently in the `sealed` state, unpaginated.
    ///
    /// Serves two launch/foreground jobs the paginated `timeline` can't:
    ///  • the §5.4 unlock sweep — evaluate every sealed card against trusted
    ///    time and unlock those that are due;
    ///  • §5.7 notification re-scheduling — "re-scan all sealed cards and
    ///    re-schedule on every launch", since an uninstall wipes the pending
    ///    queue.
    ///
    /// Both need the *whole* set, so this is deliberately not paged. Drafts and
    /// unlocked cards are excluded. Order is unspecified — callers iterate the
    /// full set rather than depending on position.
    func sealedPostcards() async throws -> [Postcard]

    // MARK: - Update

    /// Persists changes made to an existing postcard (state transitions, edits
    /// within the §5.3 window, decoration changes).
    ///
    /// - Throws: if the write fails (§7.2).
    func update(_ postcard: Postcard) async throws

    // MARK: - Delete

    /// Permanently deletes the postcard — no recovery bin (§5.3 / decision
    /// record). Permitted in any state, including a locked card; the caller
    /// owns the §5.3 confirmation UX, the store just deletes.
    ///
    /// Deleting a card that is not present is a no-op, not an error.
    func delete(_ postcard: Postcard) async throws
}
