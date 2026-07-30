//
//  PostcardLifecycle.swift
//  DearFutureMe
//
//  The §5.3 lock state machine: draft → sealed → unlocked. This is the layer
//  §8 calls "the trust contract" — sealed cards are never prematurely revealed —
//  so its correctness matters more than anything visual (BUILD-PLAN step 2c).
//
//  Scope of this file: TRANSITIONS ONLY. Two of them:
//
//    seal(_:unlockDate:)   draft   → sealed     (validated)
//    unlockIfDue(_:)       sealed  → unlocked   (when trusted time reaches the date)
//
//  There is no transition OUT of `unlocked` — it is terminal (§5.3.5: "becomes
//  permanently readable"). And `draft` never jumps straight to `unlocked`; a card
//  only unlocks once sealed.
//
//  Deliberately NOT here:
//   • Persistence. A transition mutates the passed `Postcard` (a reference type)
//     in place and returns; the caller persists via `PostcardStore.update`. The
//     lifecycle never touches the store — separation of "what state is legal"
//     from "where it's written".
//   • Notifications, and the §5.3.5 purge of prior edit versions. Both are step 3
//     work; there is no version history to purge yet. `unlockIfDue` only reports
//     that an unlock happened so step 3 can hang that behaviour off it.
//   • Deletion. Permitted in any state (§5.3.4) and owned by the store; it is not
//     a lifecycle transition, so it isn't modelled as one.
//
//  ── Why this consults TrustedClock and never Date() ────────────────────────
//  Unlock is a §5.4 decision: evaluated against trusted time, never the device
//  clock (which the user can wind forward to pop a card early). So both
//  time-sensitive transitions read `TrustedClock.now()`, and when trusted time
//  is unavailable (`.neverSynced`) they refuse to act — seal throws, unlock stays
//  locked (§7.1: "Trusted time unreachable → stay locked, quiet waiting state").
//  There is no device-clock fallback anywhere in this file.
//

import Foundation

@MainActor
struct PostcardLifecycle {

    /// The §5.3 edit window: one week from creation. A plain constant — the
    /// window is a fixed product rule, not configuration.
    static let editWindow: TimeInterval = 7 * 24 * 60 * 60

    private let clock: TrustedClock

    init(clock: TrustedClock) {
        self.clock = clock
    }

    // MARK: - draft → sealed

    /// Seals a draft for the given `unlockDate`.
    ///
    /// Preconditions, each a distinct `SealError` so the composer can react
    /// precisely:
    ///  • The card must be a `draft` — only drafts seal. Re-sealing a sealed card
    ///    or a terminal unlocked one is a programming error, surfaced as
    ///    `.notADraft`.
    ///  • `unlockDate` must be strictly in the future relative to **trusted**
    ///    now (§5.3.1). Equal-to-now counts as not-future and is rejected —
    ///    otherwise the card would satisfy `unlockIfDue` in the same instant.
    ///  • Trusted time must be available. With no server anchor we cannot verify
    ///    the date is genuinely in the future, and §5.4 forbids falling back to
    ///    the device clock, so sealing is refused rather than guessed.
    ///
    /// On success it sets `unlockDate`, derives `editableUntil` (the truncated
    /// edit window, below), flips `state` to `.sealed`, and returns. It does not
    /// persist — the caller does.
    func seal(_ postcard: Postcard, unlockDate: Date) throws {
        guard postcard.state == .draft else {
            throw SealError.notADraft(postcard.state)
        }
        guard case .trusted(let now) = clock.now() else {
            throw SealError.trustedTimeUnavailable
        }
        guard unlockDate > now else {
            throw SealError.unlockDateNotInFuture
        }

        postcard.unlockDate = unlockDate
        postcard.editableUntil = Self.editableUntil(createdAt: postcard.createdAt, unlockDate: unlockDate)
        postcard.state = .sealed
    }

    /// The end of the §5.3.3 edit window: one week after creation, **truncated to
    /// the unlock date if that arrives first** ("Window truncates if the unlock
    /// date arrives first"). A card unlocking in three days is editable for three
    /// days, not seven; a card unlocking in a year is editable for the full week.
    ///
    /// Pure arithmetic over two known instants — no clock needed, which is why
    /// the truncation is directly assertable in tests.
    static func editableUntil(createdAt: Date, unlockDate: Date) -> Date {
        min(createdAt.addingTimeInterval(editWindow), unlockDate)
    }

    // MARK: - sealed → unlocked

    /// Unlocks the card iff it is sealed and trusted time has reached its
    /// `unlockDate` (§5.4: `unlocked = trustedNow >= unlockDate`).
    ///
    /// A no-op — returning `false` — in every other case, so it is safe to call
    /// on any card at any time (e.g. a launch/foreground sweep):
    ///  • Not sealed: a `draft` never unlocks, and `unlocked` is terminal.
    ///  • No `unlockDate`: a sealed card should always carry one (the §5.3
    ///    invariant the schema can't enforce — see Models.swift); if it somehow
    ///    doesn't, stay locked rather than crash.
    ///  • `.neverSynced`: trusted time unreachable → stay locked (§7.1). Note this
    ///    is *not* a Date() fallback — no anchor means no unlock, full stop.
    ///  • Not yet due: `trustedNow < unlockDate`.
    ///
    /// - Returns: `true` only when it transitioned the card to `.unlocked`, so
    ///   step 3 can trigger the notify / purge / reveal that follow an unlock.
    @discardableResult
    func unlockIfDue(_ postcard: Postcard) -> Bool {
        guard postcard.state == .sealed else { return false }
        guard let unlockDate = postcard.unlockDate else { return false }
        guard case .trusted(let now) = clock.now() else { return false }
        guard now >= unlockDate else { return false }

        postcard.state = .unlocked
        return true
    }

    // MARK: - Errors

    /// Why a `seal` was rejected. `Equatable` so tests can assert the exact
    /// reason, and so the composer can map each case to its own copy.
    enum SealError: Error, Equatable {
        /// The card wasn't a `draft`. Carries the offending state.
        case notADraft(PostcardState)
        /// `unlockDate` was at or before trusted now — nothing to wait for.
        case unlockDateNotInFuture
        /// No trusted time to validate against (`.neverSynced`); §5.4 forbids
        /// using the device clock instead, so the seal can't be verified.
        case trustedTimeUnavailable
    }
}
