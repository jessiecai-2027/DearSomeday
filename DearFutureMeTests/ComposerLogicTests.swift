//
//  ComposerLogicTests.swift
//  DearFutureMeTests
//
//  The composer's testable core: the "chosen local date and time" unlock rule
//  (across time zones, minute precision) and the seal-error copy. The SwiftUI
//  composer itself is not unit-tested (§8: no UI tests).
//

import Testing
import Foundation
@testable import DearFutureMe

@MainActor
struct ComposerLogicTests {

    private func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    // MARK: - Chosen date+time unlock instant

    @Test func unlockInstantPreservesTheChosenLocalDateAndTime() {
        let cal = calendar("America/New_York")
        let chosen = cal.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 15, minute: 42))!

        let unlock = ComposerLogic.unlockInstant(from: chosen, calendar: cal)

        let got = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: unlock)
        #expect(got.year == 2026 && got.month == 8 && got.day == 20)
        #expect(got.hour == 15 && got.minute == 42 && got.second == 0)
    }

    @Test func unlockInstantDropsSecondsToMinutePrecision() {
        let cal = calendar("America/New_York")
        let chosen = cal.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 15, minute: 42, second: 37))!

        let unlock = ComposerLogic.unlockInstant(from: chosen, calendar: cal)

        // Same minute, seconds zeroed.
        let got = cal.dateComponents([.hour, .minute, .second], from: unlock)
        #expect(got.hour == 15 && got.minute == 42 && got.second == 0)
    }

    @Test func unlockInstantIsAnAbsoluteInstantTiedToTheCalendarZone() {
        // Same wall-clock date+time, two zones → two different absolute instants,
        // each preserving its own local time. Confirms the components are
        // interpreted in the given zone, then frozen as a UTC instant (§5.3).
        let ny = calendar("America/New_York")
        let tokyo = calendar("Asia/Tokyo")
        let components = DateComponents(year: 2026, month: 6, day: 15, hour: 20, minute: 0)

        let nyUnlock = ComposerLogic.unlockInstant(from: ny.date(from: components)!, calendar: ny)
        let tokyoUnlock = ComposerLogic.unlockInstant(from: tokyo.date(from: components)!, calendar: tokyo)

        #expect(nyUnlock != tokyoUnlock)
        #expect(ny.dateComponents([.hour], from: nyUnlock).hour == 20)
        #expect(tokyo.dateComponents([.hour], from: tokyoUnlock).hour == 20)
    }

    // MARK: - Seal error copy

    @Test func sealErrorCopyIsPlainNonEmptyAndDistinct() {
        let notADraft = ComposerLogic.sealErrorCopy(.notADraft(.sealed))
        let notFuture = ComposerLogic.sealErrorCopy(.unlockDateNotInFuture)
        let noClock = ComposerLogic.sealErrorCopy(.trustedTimeUnavailable)

        #expect(!notADraft.isEmpty)
        #expect(!notFuture.isEmpty)
        #expect(!noClock.isEmpty)
        // Each case gets its own message so the user knows what to do.
        #expect(Set([notADraft, notFuture, noClock]).count == 3)
    }
}
