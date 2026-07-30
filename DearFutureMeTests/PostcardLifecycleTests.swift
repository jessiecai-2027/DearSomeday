//
//  PostcardLifecycleTests.swift
//  DearFutureMeTests
//
//  Exercises the §5.3 lock state machine: the two legal transitions
//  (draft → sealed, sealed → unlocked), the guards that reject illegal ones,
//  the §5.3.3 edit-window truncation, and — the trust contract — that unlock is
//  governed by TrustedClock, never the device clock (§5.4).
//
//  Trusted time is controlled through the existing TrustedClock seam: a store
//  pre-seeded with a `TrustedTimeSync` anchor plus a fixed `uptime`. With
//  `uptime` equal to the anchor's `uptimeAtSync`, the projection has zero delta,
//  so `clock.now()` is exactly the seeded instant — a deterministic "trusted
//  now" the tests dial in directly.
//

import Testing
import Foundation
@testable import DearFutureMe

@MainActor
struct PostcardLifecycleTests {

    // MARK: - Fixtures

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86_400
    private let week: TimeInterval = 7 * 86_400

    /// A clock whose trusted `now()` is exactly `trustedNow` (zero projection
    /// delta), for a lifecycle wired to a known instant.
    private func lifecycle(trustedNow: Date) -> PostcardLifecycle {
        let anchor = TrustedTimeSync(lastTrustedTime: trustedNow, uptimeAtSync: 1_000)
        let clock = TrustedClock(store: InMemoryTrustedTimeStore(lastSync: anchor), uptime: { 1_000 })
        return PostcardLifecycle(clock: clock)
    }

    /// A lifecycle whose clock has never synced — trusted time unavailable.
    private func neverSyncedLifecycle() -> PostcardLifecycle {
        PostcardLifecycle(clock: TrustedClock(store: InMemoryTrustedTimeStore(), uptime: { 1_000 }))
    }

    private func draft(createdAt: Date) -> Postcard {
        Postcard(createdAt: createdAt, state: .draft)
    }

    // MARK: - draft → sealed

    @Test func sealMovesDraftToSealedAndSetsWindow() throws {
        let lc = lifecycle(trustedNow: t0)
        let card = draft(createdAt: t0)

        try lc.seal(card, unlockDate: t0.addingTimeInterval(30 * day))

        #expect(card.state == .sealed)
        #expect(card.unlockDate == t0.addingTimeInterval(30 * day))
        // Unlock is far out, so the edit window is the full week from creation.
        #expect(card.editableUntil == t0.addingTimeInterval(week))
    }

    @Test func sealRejectsUnlockDateAtOrBeforeTrustedNow() {
        let lc = lifecycle(trustedNow: t0)

        // Exactly now is not "in the future".
        let atNow = draft(createdAt: t0)
        #expect(throws: PostcardLifecycle.SealError.unlockDateNotInFuture) {
            try lc.seal(atNow, unlockDate: t0)
        }
        #expect(atNow.state == .draft)          // unchanged

        // In the past.
        let past = draft(createdAt: t0)
        #expect(throws: PostcardLifecycle.SealError.unlockDateNotInFuture) {
            try lc.seal(past, unlockDate: t0.addingTimeInterval(-day))
        }
        #expect(past.state == .draft)
    }

    @Test func sealRejectsNonDraft() throws {
        let lc = lifecycle(trustedNow: t0)

        let sealed = draft(createdAt: t0)
        try lc.seal(sealed, unlockDate: t0.addingTimeInterval(day))
        #expect(throws: PostcardLifecycle.SealError.notADraft(.sealed)) {
            try lc.seal(sealed, unlockDate: t0.addingTimeInterval(2 * day))
        }
    }

    @Test func sealRequiresTrustedTime() {
        let lc = neverSyncedLifecycle()
        let card = draft(createdAt: t0)

        #expect(throws: PostcardLifecycle.SealError.trustedTimeUnavailable) {
            try lc.seal(card, unlockDate: t0.addingTimeInterval(30 * day))
        }
        #expect(card.state == .draft)           // nothing mutated
        #expect(card.unlockDate == nil)
    }

    // MARK: - Edit-window truncation (§5.3.3)

    @Test func editWindowTruncatesWhenUnlockArrivesBeforeAWeek() throws {
        let lc = lifecycle(trustedNow: t0)
        let card = draft(createdAt: t0)

        // Unlock in 3 days — sooner than the 1-week window, so it truncates.
        try lc.seal(card, unlockDate: t0.addingTimeInterval(3 * day))
        #expect(card.editableUntil == t0.addingTimeInterval(3 * day))
    }

    @Test func editableUntilIsTheEarlierOfWeekAndUnlock() {
        // Pure helper: the min() of (createdAt + week) and unlockDate.
        #expect(PostcardLifecycle.editableUntil(createdAt: t0, unlockDate: t0.addingTimeInterval(3 * day))
                == t0.addingTimeInterval(3 * day))
        #expect(PostcardLifecycle.editableUntil(createdAt: t0, unlockDate: t0.addingTimeInterval(365 * day))
                == t0.addingTimeInterval(week))
    }

    // MARK: - sealed → unlocked

    @Test func unlockWhenTrustedTimeReachesUnlockDate() throws {
        let unlockDate = t0.addingTimeInterval(day)

        // Seal against an earlier trusted now, then evaluate at a later one.
        let sealer = lifecycle(trustedNow: t0)
        let card = draft(createdAt: t0)
        try sealer.seal(card, unlockDate: unlockDate)

        // Trusted now is exactly the unlock instant → due (>=).
        let atUnlock = lifecycle(trustedNow: unlockDate)
        #expect(atUnlock.unlockIfDue(card) == true)
        #expect(card.state == .unlocked)
    }

    @Test func staysLockedBeforeUnlockDate() throws {
        let card = draft(createdAt: t0)
        let sealer = lifecycle(trustedNow: t0)
        try sealer.seal(card, unlockDate: t0.addingTimeInterval(2 * day))

        // Trusted now is a day in — not yet due.
        let oneDayIn = lifecycle(trustedNow: t0.addingTimeInterval(day))
        #expect(oneDayIn.unlockIfDue(card) == false)
        #expect(card.state == .sealed)
    }

    @Test func staysLockedWhenTrustedTimeUnavailable() throws {
        // Seal with a real clock, then evaluate under a never-synced one: even
        // though the unlock date is long past in device terms, no trusted anchor
        // means no unlock (§7.1). This is the offline/uninitialised case.
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: t0.addingTimeInterval(day))

        #expect(neverSyncedLifecycle().unlockIfDue(card) == false)
        #expect(card.state == .sealed)
    }

    // MARK: - Terminal state

    @Test func unlockedIsTerminal() throws {
        let unlockDate = t0.addingTimeInterval(day)
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: unlockDate)

        let lc = lifecycle(trustedNow: unlockDate)
        #expect(lc.unlockIfDue(card) == true)       // first unlock
        #expect(lc.unlockIfDue(card) == false)      // already unlocked → no-op
        #expect(card.state == .unlocked)

        // And it can never be re-sealed.
        #expect(throws: PostcardLifecycle.SealError.notADraft(.unlocked)) {
            try lc.seal(card, unlockDate: unlockDate.addingTimeInterval(week))
        }
    }

    @Test func draftNeverUnlocks() {
        // A draft is not sealed, so unlockIfDue is a no-op even past any date.
        let card = draft(createdAt: t0)
        card.unlockDate = t0.addingTimeInterval(-day)   // even with a past date attached
        #expect(lifecycle(trustedNow: t0).unlockIfDue(card) == false)
        #expect(card.state == .draft)
    }
}
