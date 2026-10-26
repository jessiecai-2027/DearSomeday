//
//  PostcardLifecycleTests.swift
//  DearSomedayTests
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
@testable import DearSomeday

@MainActor
struct PostcardLifecycleTests {

    // MARK: - Fixtures

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400
    private let week: TimeInterval = 7 * 86_400

    /// A clock whose trusted `now()` is exactly `trustedNow` (zero projection
    /// delta), for a lifecycle wired to a known instant.
    private func lifecycle(trustedNow: Date) -> PostcardLifecycle {
        let anchor = TrustedTimeSync(lastTrustedTime: trustedNow, uptimeAtSync: 1_000)
        let clock = TrustedClock(store: InMemoryTrustedTimeStore(lastSync: anchor), uptime: { 1_000 })
        return PostcardLifecycle(clock: clock)
    }

    /// A lifecycle over a hand-built anchor and a fixed current uptime, so the
    /// adversarial cases can dial the raw §5.4 inputs directly: a tiny uptime
    /// delta (tampering), or `currentUptime < uptimeAtSync` (an offline reboot,
    /// which no real device could stage in a test).
    private func lifecycle(
        lastTrustedTime: Date,
        uptimeAtSync: TimeInterval,
        currentUptime: TimeInterval
    ) -> PostcardLifecycle {
        let anchor = TrustedTimeSync(lastTrustedTime: lastTrustedTime, uptimeAtSync: uptimeAtSync)
        let clock = TrustedClock(store: InMemoryTrustedTimeStore(lastSync: anchor), uptime: { currentUptime })
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

    @Test func unlocksOnceTrustedTimePassesUnlockDate() throws {
        // (3) The legitimate unlock: trusted time moves strictly past the date.
        let unlockDate = t0.addingTimeInterval(day)
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: unlockDate)

        // A day beyond the unlock instant → due.
        let dayAfter = lifecycle(trustedNow: unlockDate.addingTimeInterval(day))
        #expect(dayAfter.unlockIfDue(card) == true)
        #expect(card.state == .unlocked)
    }

    @Test func unlockWhenTrustedTimeReachesUnlockDate() throws {
        // (4) Boundary: trusted now is *exactly* the unlock instant. The rule is
        // `trustedNow >= unlockDate` (§5.4), so the equal instant unlocks.
        let unlockDate = t0.addingTimeInterval(day)

        // Seal against an earlier trusted now, then evaluate at the exact instant.
        let sealer = lifecycle(trustedNow: t0)
        let card = draft(createdAt: t0)
        try sealer.seal(card, unlockDate: unlockDate)

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

    // MARK: - Edit window (§5.3.3)

    @Test func sealedCardEditableInsideWindowNotOutside() throws {
        // Unlock a year out → window is the full week from creation.
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: t0.addingTimeInterval(365 * day))

        // Day 3: inside the week → editable.
        #expect(lifecycle(trustedNow: t0.addingTimeInterval(3 * day)).isEditable(card) == true)
        // Exactly one week: window has ended (strict bound) → not editable.
        #expect(lifecycle(trustedNow: t0.addingTimeInterval(week)).isEditable(card) == false)
        // Past the week → not editable.
        #expect(lifecycle(trustedNow: t0.addingTimeInterval(8 * day)).isEditable(card) == false)
    }

    @Test func editWindowHonoursUnlockTruncation() throws {
        // Unlock in 3 days → window truncates to 3 days.
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: t0.addingTimeInterval(3 * day))

        #expect(lifecycle(trustedNow: t0.addingTimeInterval(2 * day)).isEditable(card) == true)
        // At the unlock instant the truncated window closes and the card unlocks
        // — never editable at the moment it unlocks.
        #expect(lifecycle(trustedNow: t0.addingTimeInterval(3 * day)).isEditable(card) == false)
    }

    @Test func notEditableWhenTrustedTimeUnavailable() throws {
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: t0.addingTimeInterval(30 * day))

        // Well inside the window in device terms, but no trusted anchor to
        // confirm it → err closed.
        #expect(neverSyncedLifecycle().isEditable(card) == false)
    }

    @Test func draftAndUnlockedAreNotEditable() throws {
        // A draft has no sealed window.
        let draftCard = draft(createdAt: t0)
        #expect(lifecycle(trustedNow: t0).isEditable(draftCard) == false)

        // Unlocked is terminal → never editable.
        let unlockDate = t0.addingTimeInterval(day)
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: unlockDate)
        let atUnlock = lifecycle(trustedNow: unlockDate)
        atUnlock.unlockIfDue(card)
        #expect(card.state == .unlocked)
        #expect(atUnlock.isEditable(card) == false)
    }

    // MARK: - Adversarial: tampering / offline reboot (§5.4)
    //
    // The trust contract (§8): a sealed card is never prematurely revealed. Each
    // of these asserts on the *lock state* after an attack — not on the computed
    // instant — because "did the card open?" is the property that actually
    // matters. TrustedClock has no device-clock input, so the attacks are staged
    // purely through the §5.4 inputs: the monotonic uptime and the cached anchor.

    @Test func tamperingDeviceClockForwardKeepsCardLocked() throws {
        // Card due in an hour.
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: t0.addingTimeInterval(hour))

        // The user winds the *device* clock a year forward to force the card. But
        // trusted time never reads that clock — it advances only by the monotonic
        // uptime delta, held here at 10s (≈ no real time elapsed). trustedNow is
        // ~t0 + 10s, nowhere near the unlock date.
        let tampered = lifecycle(lastTrustedTime: t0, uptimeAtSync: 50_000, currentUptime: 50_010)

        #expect(tampered.unlockIfDue(card) == false)
        #expect(card.state == .sealed)                  // stays locked
    }

    @Test func offlineRebootBeforeUnlockKeepsCardLocked() throws {
        // Card due in an hour, sealed while the device had a high uptime.
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: t0.addingTimeInterval(hour))

        // Device reboots offline: uptime resets to ~5s and no fresh sync lands.
        // The reboot's negative delta is clamped away, so cached trusted time is
        // the last sync instant (t0) — still short of the unlock date.
        let rebooted = lifecycle(lastTrustedTime: t0, uptimeAtSync: 50_000, currentUptime: 5)

        #expect(rebooted.unlockIfDue(card) == false)
        #expect(card.state == .sealed)                  // stays locked
    }

    @Test func rebootNeverDropsTrustedTimeBelowLastSync() throws {
        // Card due in an hour, sealed at t0.
        let card = draft(createdAt: t0)
        try lifecycle(trustedNow: t0).seal(card, unlockDate: t0.addingTimeInterval(hour))

        // The device later synced at t0 + 2h (uptime 50_000) — already past the
        // unlock date — but the card hadn't been re-evaluated. Then it reboots
        // (uptime → 5s) with no fresh sync. The clamp holds trustedNow at the last
        // sync (t0 + 2h) instead of letting the backwards uptime drag it below,
        // so the legitimately-due card unlocks. Were the lower bound not enforced,
        // the negative delta would push trustedNow before the unlock date and the
        // card would wrongly stay locked — so this asserts the clamp via state.
        let afterReboot = lifecycle(lastTrustedTime: t0.addingTimeInterval(2 * hour),
                                    uptimeAtSync: 50_000, currentUptime: 5)

        #expect(afterReboot.unlockIfDue(card) == true)
        #expect(card.state == .unlocked)                // opens; trustedNow held at ≥ last sync
    }
}
