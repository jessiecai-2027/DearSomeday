//
//  UnlockCoordinatorTests.swift
//  DearSomedayTests
//
//  The verification for the launch/foreground unlock sweep, driven by a fake
//  clock so "time passes" is instant: the trusted clock is anchored to a known
//  instant, and `refresh()` is fed a later instant through a FixedServerClock.
//  No real waiting, device-clock changes, or UI.
//
//  What these prove, end to end:
//   • a due sealed card unlocks AND is persisted (the core loop's payoff);
//   • a not-yet-due card stays sealed;
//   • the unlock only happens once the injected instant advances past the date;
//   • an unavailable source keeps everything sealed;
//   • the sweep is idempotent and ignores unlocked cards.
//

import Testing
import Foundation
@testable import DearSomeday

@MainActor
struct UnlockCoordinatorTests {

    // MARK: - Fixtures

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let hour: TimeInterval = 3_600

    /// Wires an in-memory store + a trusted clock whose "now" is dial-able. With
    /// `uptime == uptimeAtSync` (both 1_000) the projection delta is zero, so
    /// projected now is exactly `anchoredAt`. `serverNow` is the injected value
    /// a `runSweep` refresh will adopt (nil = source unavailable).
    private func makeCoordinator(
        anchoredAt: Date?,
        serverNow: Date?
    ) -> (store: InMemoryPostcardStore, coordinator: UnlockCoordinator) {
        let anchor = anchoredAt.map { TrustedTimeSync(lastTrustedTime: $0, uptimeAtSync: 1_000) }
        let clock = TrustedClock(
            store: InMemoryTrustedTimeStore(lastSync: anchor),
            uptime: { 1_000 },
            source: FixedServerClock(serverNow)
        )
        let lifecycle = PostcardLifecycle(clock: clock)
        let store = InMemoryPostcardStore()
        let coordinator = UnlockCoordinator(store: store, lifecycle: lifecycle, clock: clock)
        return (store, coordinator)
    }

    private func sealedCard(_ title: String, unlock: Date) -> Postcard {
        Postcard(title: title, unlockDate: unlock, state: .sealed)
    }

    // MARK: - The payoff: due card unlocks and persists

    @Test func sweepUnlocksADueCardAndPersistsIt() async throws {
        // Trusted now is t0; the card was due an hour ago. Server re-reports t0
        // (no change) — the card is already past due.
        let (store, coordinator) = makeCoordinator(anchoredAt: t0, serverNow: t0)
        let card = sealedCard("due", unlock: t0.addingTimeInterval(-hour))
        try await store.create(card)

        let flipped = await coordinator.runSweep()

        #expect(flipped.map(\.id) == [card.id])
        // Persisted, not just mutated in memory.
        #expect(try await store.postcard(withID: card.id)?.state == .unlocked)
        // And it has left the sealed set.
        #expect(try await store.sealedPostcards().isEmpty)
    }

    // MARK: - Not-yet-due stays sealed

    @Test func sweepLeavesANotYetDueCardSealed() async throws {
        let (store, coordinator) = makeCoordinator(anchoredAt: t0, serverNow: t0)
        let card = sealedCard("future", unlock: t0.addingTimeInterval(hour))
        try await store.create(card)

        let flipped = await coordinator.runSweep()

        #expect(flipped.isEmpty)
        #expect(try await store.postcard(withID: card.id)?.state == .sealed)
    }

    // MARK: - Unlock tracks the SERVER instant, not the device

    @Test func cardUnlocksOnlyAfterTheServerSyncAdvancesPastTheUnlockDate() async throws {
        // Anchored at t0; card unlocks at t0 + 1h. Before any advance it is not
        // due — unlockDueCards (no sync) is a no-op.
        let (store, coordinator) = makeCoordinator(anchoredAt: t0, serverNow: t0.addingTimeInterval(2 * hour))
        let card = sealedCard("waits", unlock: t0.addingTimeInterval(hour))
        try await store.create(card)

        let beforeSync = await coordinator.unlockDueCards()
        #expect(beforeSync.isEmpty)
        #expect(try await store.postcard(withID: card.id)?.state == .sealed)

        // runSweep pulls the injected instant (t0 + 2h), which is now past the
        // unlock date, so the card flips.
        let afterSync = await coordinator.runSweep()
        #expect(afterSync.map(\.id) == [card.id])
        #expect(try await store.postcard(withID: card.id)?.state == .unlocked)
    }

    // MARK: - Never synced → stay locked (§7.1)

    @Test func sweepWithAnUnreachableServerKeepsCardsSealed() async throws {
        // No anchor ever, and the server is offline (nil): trusted time is
        // unknown, so even a long-past unlock date must NOT open the card.
        let (store, coordinator) = makeCoordinator(anchoredAt: nil, serverNow: nil)
        let card = sealedCard("locked", unlock: t0.addingTimeInterval(-100 * hour))
        try await store.create(card)

        let flipped = await coordinator.runSweep()

        #expect(flipped.isEmpty)
        #expect(try await store.postcard(withID: card.id)?.state == .sealed)
    }

    // MARK: - Multiple / mixed / idempotent

    @Test func sweepUnlocksEveryDueCardAndLeavesTheRest() async throws {
        let (store, coordinator) = makeCoordinator(anchoredAt: t0, serverNow: t0)
        let dueA = sealedCard("dueA", unlock: t0.addingTimeInterval(-hour))
        let dueB = sealedCard("dueB", unlock: t0.addingTimeInterval(-2 * hour))
        let future = sealedCard("future", unlock: t0.addingTimeInterval(hour))
        let alreadyOpen = Postcard(title: "open", unlockDate: t0.addingTimeInterval(-3 * hour), state: .unlocked)
        for pc in [dueA, dueB, future, alreadyOpen] { try await store.create(pc) }

        let flipped = await coordinator.runSweep()

        #expect(Set(flipped.map(\.title)) == ["dueA", "dueB"])
        #expect(try await store.postcard(withID: future.id)?.state == .sealed)
        // The sealed set is now just the still-locked future card.
        #expect(try await store.sealedPostcards().map(\.title) == ["future"])
    }

    @Test func runningTheSweepTwiceFlipsNothingTheSecondTime() async throws {
        let (store, coordinator) = makeCoordinator(anchoredAt: t0, serverNow: t0)
        try await store.create(sealedCard("due", unlock: t0.addingTimeInterval(-hour)))

        #expect(await coordinator.runSweep().count == 1)
        #expect(await coordinator.runSweep().isEmpty)     // already unlocked → no-op
    }

    @Test func repeatedLiveChecksAreIdempotentAndDoNotContactTheServer() async throws {
        let server = CountingServerClock(instant: t0.addingTimeInterval(10 * hour))
        let anchor = TrustedTimeSync(lastTrustedTime: t0, uptimeAtSync: 1_000)
        let clock = TrustedClock(
            store: InMemoryTrustedTimeStore(lastSync: anchor),
            uptime: { 1_000 },
            source: server
        )
        let lifecycle = PostcardLifecycle(clock: clock)
        let store = InMemoryPostcardStore()
        let coordinator = UnlockCoordinator(store: store, lifecycle: lifecycle, clock: clock)
        let card = sealedCard("due", unlock: t0.addingTimeInterval(-hour))
        try await store.create(card)

        #expect(await coordinator.unlockDueCards().map(\.id) == [card.id])
        #expect(await coordinator.unlockDueCards().isEmpty)
        #expect(await coordinator.unlockDueCards().isEmpty)
        #expect(await server.requestCount == 0)
    }

    @Test func sweepWithNoSealedCardsIsAHarmlessNoOp() async throws {
        let (store, coordinator) = makeCoordinator(anchoredAt: t0, serverNow: t0)
        try await store.create(Postcard(title: "open", unlockDate: t0, state: .unlocked))

        #expect(await coordinator.runSweep().isEmpty)
    }
}

private actor CountingServerClock: TimeSource {
    let instant: Date?
    private(set) var requestCount = 0

    init(instant: Date?) {
        self.instant = instant
    }

    func currentInstant() async -> Date? {
        requestCount += 1
        return instant
    }
}
