//
//  ComposerLogicTests.swift
//  DearFutureMeTests
//
//  The composer's testable core: the "9:00am local on the chosen day" unlock
//  rule (across time zones and a year boundary) and the seal-error copy. The
//  SwiftUI composer itself is not unit-tested (§8: no UI tests).
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

    // MARK: - 9am-local unlock instant

    @Test func unlockInstantIsNineAMLocalOnTheChosenDay() {
        let cal = calendar("America/New_York")
        // An afternoon instant on 2026-08-20; only the day should survive.
        let day = cal.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 15, minute: 42))!

        let unlock = ComposerLogic.unlockInstant(onDayOf: day, calendar: cal)

        let got = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: unlock)
        #expect(got.year == 2026 && got.month == 8 && got.day == 20)
        #expect(got.hour == 9 && got.minute == 0 && got.second == 0)
    }

    @Test func unlockInstantKeepsTheChosenDayEvenLateAtNight() {
        // 23:30 must not roll into the next day when we set the time to 09:00.
        let cal = calendar("Asia/Tokyo")
        let day = cal.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 30))!

        let unlock = ComposerLogic.unlockInstant(onDayOf: day, calendar: cal)

        let got = cal.dateComponents([.year, .month, .day, .hour], from: unlock)
        #expect(got.year == 2026 && got.month == 12 && got.day == 31 && got.hour == 9)
    }

    @Test func unlockInstantIsAnAbsoluteInstantTiedToTheCalendarZone() {
        // Same wall-clock day, two zones → two different absolute instants,
        // exactly 9am apart in each local zone. Confirms 9am is interpreted in
        // the given zone, then frozen as a UTC instant (§5.3).
        let ny = calendar("America/New_York")
        let tokyo = calendar("Asia/Tokyo")
        let dayComponents = DateComponents(year: 2026, month: 6, day: 15, hour: 12)

        let nyUnlock = ComposerLogic.unlockInstant(onDayOf: ny.date(from: dayComponents)!, calendar: ny)
        let tokyoUnlock = ComposerLogic.unlockInstant(onDayOf: tokyo.date(from: dayComponents)!, calendar: tokyo)

        #expect(nyUnlock != tokyoUnlock)
        #expect(ny.dateComponents([.hour], from: nyUnlock).hour == 9)
        #expect(tokyo.dateComponents([.hour], from: tokyoUnlock).hour == 9)
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
