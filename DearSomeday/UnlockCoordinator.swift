//
//  UnlockCoordinator.swift
//  DearSomeday
//
//  The launch/foreground unlock sweep — where the three foundation layers
//  finally meet: it refreshes device time, asks the lifecycle which sealed
//  cards are due (§5.3), and persists the ones that flip (§3 store). This is the
//  runtime enforcement of the trust contract: no card unlocks except through
//  here, and here consults the shared clock abstraction.
//
//  ── Two entry points ───────────────────────────────────────────────────────
//   runSweep()        the full "on launch/foreground" job: sync, then unlock.
//   unlockDueCards()  the sync-free half: evaluate + persist against the current
//                     trusted time. Split out so tests can drive the unlock
//                     logic without resampling the wall clock.
//
//  ── Failure handling (§7.2) ────────────────────────────────────────────────
//  A read failure (sealedPostcards throws) makes the pass a no-op; the next
//  sweep retries. A *write* failure after a flip rolls the in-memory state back
//  to `.sealed`, so a card is never left "unlocked in memory, sealed on disk":
//  the flip is atomic — persisted or not attempted. The next sweep retries it.
//

import Foundation

@MainActor
final class UnlockCoordinator {

    private let store: PostcardStore
    private let lifecycle: PostcardLifecycle
    private let clock: TrustedClock

    init(store: PostcardStore, lifecycle: PostcardLifecycle, clock: TrustedClock) {
        self.store = store
        self.lifecycle = lifecycle
        self.clock = clock
    }

    /// The launch/foreground sequence: refresh from device time, then unlock
    /// every card that is now due. Per-card write failures are absorbed (see
    /// `unlockDueCards`).
    ///
    /// - Returns: the cards that transitioned to `.unlocked` this pass, so a
    ///   later step (§5.7 notify, §5.3.5 reveal/purge) can hang behaviour off it.
    @discardableResult
    func runSweep() async -> [Postcard] {
        await clock.refresh()
        return await unlockDueCards()
    }

    /// Evaluates every sealed card against the *current* trusted time and
    /// persists those that unlock. Does not sync — the caller decides whether a
    /// fresh wall-clock sample is needed first.
    @discardableResult
    func unlockDueCards() async -> [Postcard] {
        let sealed: [Postcard]
        do {
            sealed = try await store.sealedPostcards()
        } catch {
            return []                       // transient read failure → retry next sweep
        }

        var flipped: [Postcard] = []
        for card in sealed {
            // unlockIfDue mutates `state` in place and returns true only on a
            // real transition; it already refuses to act on `.neverSynced` or a
            // not-yet-due card (§5.4), so no trusted-time check is needed here.
            guard lifecycle.unlockIfDue(card) else { continue }
            do {
                try await store.update(card)
                flipped.append(card)
            } catch {
                // Persist failed (e.g. storage full, §7.2). Roll the in-memory
                // flip back so the card stays consistently sealed everywhere;
                // the next sweep will try again.
                card.state = .sealed
            }
        }
        return flipped
    }
}
