//
//  FixedServerClock.swift
//  DearSomedayTests
//
//  A `TimeSource` double that returns a fixed instant (or nil). It lets tests
//  drive `TrustedClock.refresh()` deterministically. Immutable so it stays
//  Sendable; a test that needs a different instant just makes a new one.
//
//  `nonisolated` mirrors the production `DeviceTimeSource`, so `currentInstant()`
//  satisfies the protocol identically.
//

import Foundation
@testable import DearSomeday

nonisolated final class FixedServerClock: TimeSource {

    /// The instant the source reports, or nil to simulate an unavailable source.
    private let instant: Date?

    init(_ instant: Date?) {
        self.instant = instant
    }

    func currentInstant() async -> Date? {
        instant
    }
}
