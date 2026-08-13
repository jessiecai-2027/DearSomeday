//
//  FixedServerClock.swift
//  DearFutureMeTests
//
//  A `ServerClock` double that returns a fixed instant (or nil for "offline").
//  Lets tests drive `TrustedClock.syncFromServer()` — and therefore the unlock
//  sweep — without a network round-trip. Immutable so it stays Sendable; a test
//  that needs a different server time just makes a new one.
//
//  `nonisolated` mirrors the production `HTTPServerClock`, so `currentInstant()`
//  satisfies the protocol identically.
//

import Foundation
@testable import DearFutureMe

nonisolated final class FixedServerClock: ServerClock {

    /// The instant the server "reports", or nil to simulate an unreachable
    /// server (offline / missing Date header) — the whole point being that a
    /// nil keeps trusted time exactly where it was.
    private let instant: Date?

    init(_ instant: Date?) {
        self.instant = instant
    }

    func currentInstant() async -> Date? {
        instant
    }
}
