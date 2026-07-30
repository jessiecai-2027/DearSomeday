//
//  TrustedTimeTests.swift
//  DearFutureMeTests
//
//  Exercises the §5.4 trusted-time layer: the pure projection, the explicit
//  reboot detection, the two-outcome contract, persistence across relaunch, and
//  the monotonic sync guard. These are the "tampering / offline reboot" cases
//  §9 names as must-test — none of which a device could actually reproduce, so
//  they all ride on the injected uptime/wall-clock seams.
//
//  A note on the reboot simulation: we can't reset ProcessInfo.systemUptime, so
//  a "reboot" is modelled by handing the clock a *smaller* uptime than the one
//  it synced at. That is precisely what a real reboot does to the reading.
//

import Testing
import Foundation
@testable import DearFutureMe

@MainActor
struct TrustedTimeTests {

    // MARK: - Fixtures

    /// A fixed server instant so projections are deterministic.
    private let serverNow = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let hour: TimeInterval = 3_600

    /// A clock whose uptime is read from a mutable box, so a test can advance it
    /// (time passing) or lower it (reboot) between calls. `wallClock` is left as
    /// a controllable closure too, though `now()` never consults it.
    private func makeClock(
        store: TrustedTimeStore = InMemoryTrustedTimeStore(),
        uptime: @escaping () -> TimeInterval,
        wallClock: @escaping () -> Date = { Date(timeIntervalSinceReferenceDate: 0) }
    ) -> TrustedClock {
        TrustedClock(store: store, uptime: uptime, wallClock: wallClock)
    }

    // MARK: - Pure calculation

    @Test func projectAdvancesByMonotonicDelta() {
        // Synced at uptime 1000; now uptime 1000 + 2h → trusted time is +2h.
        let sync = TrustedTimeSync(lastTrustedTime: serverNow, uptimeAtSync: 1_000)
        let projected = TrustedTimeCalculator.project(sync, currentUptime: 1_000 + 2 * hour)
        #expect(projected == serverNow.addingTimeInterval(2 * hour))
    }

    @Test func projectClampsToLastTrustedTimeOnReboot() {
        // Synced at uptime 5000; a reboot drops it to 30. Delta is negative, so
        // the projection clamps to the synced instant — the valid lower bound.
        let sync = TrustedTimeSync(lastTrustedTime: serverNow, uptimeAtSync: 5_000)
        let projected = TrustedTimeCalculator.project(sync, currentUptime: 30)
        #expect(projected == serverNow)
    }

    @Test func rebootDetectedExactlyWhenUptimeRegresses() {
        #expect(TrustedTimeCalculator.rebooted(uptimeAtSync: 5_000, currentUptime: 30))
        #expect(!TrustedTimeCalculator.rebooted(uptimeAtSync: 5_000, currentUptime: 5_000 + hour))
        // Equal uptime is not a reboot (no regression), just no elapsed time.
        #expect(!TrustedTimeCalculator.rebooted(uptimeAtSync: 5_000, currentUptime: 5_000))
    }

    // MARK: - Two outcomes

    @Test func beforeAnySyncTimeIsNeverSynced() {
        // Even though wallClock returns a real instant, now() must NOT fall back
        // to it — the only honest answer with no server anchor is neverSynced.
        let clock = makeClock(
            uptime: { 1_000 },
            wallClock: { self.serverNow }
        )
        #expect(clock.now() == .neverSynced)
    }

    @Test func afterSyncTimeIsTrustedAndAdvances() {
        var uptime: TimeInterval = 1_000
        let clock = makeClock(uptime: { uptime })

        #expect(clock.sync(serverNow: serverNow) == .trusted(serverNow))

        // 3h of uptime elapse.
        uptime = 1_000 + 3 * hour
        #expect(clock.now() == .trusted(serverNow.addingTimeInterval(3 * hour)))
    }

    // MARK: - Offline reboot (§5.4)

    @Test func rebootAfterSyncHoldsTrustedTimeAtLowerBound() {
        var uptime: TimeInterval = 8_000
        let clock = makeClock(uptime: { uptime })
        clock.sync(serverNow: serverNow)

        // Some time passes, then the device reboots offline: uptime resets low.
        uptime = 42
        // Trusted time holds at the synced instant — it does not leap forward and
        // it does not become neverSynced. A card unlocking later stays locked.
        #expect(clock.now() == .trusted(serverNow))
    }

    // MARK: - Persistence across relaunch

    @Test func anchorSurvivesRelaunch() {
        let store = InMemoryTrustedTimeStore()

        // First launch syncs, then goes away.
        let first = makeClock(store: store, uptime: { 2_000 })
        first.sync(serverNow: serverNow)

        // Relaunch: a brand-new coordinator over the same persisted store,
        // uptime having climbed by 1h since the sync.
        let second = makeClock(store: store, uptime: { 2_000 + hour })
        #expect(second.now() == .trusted(serverNow.addingTimeInterval(hour)))
    }

    // MARK: - Monotonic sync guard (tampering / stale response)

    @Test func syncNeverOverwritesLastTrustedTimeWithEarlierValue() {
        var uptime: TimeInterval = 1_000
        let store = InMemoryTrustedTimeStore()
        let clock = makeClock(store: store, uptime: { uptime })

        clock.sync(serverNow: serverNow)

        // A later, earlier-valued response arrives (skew / replay). It must be
        // rejected — the stored anchor is untouched.
        uptime = 1_000 + hour
        let earlier = serverNow.addingTimeInterval(-10 * hour)
        clock.sync(serverNow: earlier)

        // The anchor is still the original instant paired with the original
        // uptime, so projection reflects only genuine elapsed uptime (+1h), not
        // the rewound server value.
        #expect(store.lastSync == TrustedTimeSync(lastTrustedTime: serverNow, uptimeAtSync: 1_000))
        #expect(clock.now() == .trusted(serverNow.addingTimeInterval(hour)))
    }

    @Test func syncAdoptsLaterServerInstant() {
        var uptime: TimeInterval = 1_000
        let store = InMemoryTrustedTimeStore()
        let clock = makeClock(store: store, uptime: { uptime })

        clock.sync(serverNow: serverNow)

        // A newer response, an hour of uptime later, carrying a later instant.
        uptime = 1_000 + hour
        let later = serverNow.addingTimeInterval(5 * hour)
        clock.sync(serverNow: later)

        // The anchor re-pegs to the new instant at the new uptime.
        #expect(store.lastSync == TrustedTimeSync(lastTrustedTime: later, uptimeAtSync: 1_000 + hour))
        #expect(clock.now() == .trusted(later))
    }
}
