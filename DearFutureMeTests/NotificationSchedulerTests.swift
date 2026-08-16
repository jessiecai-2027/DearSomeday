//
//  NotificationSchedulerTests.swift
//  DearFutureMeTests
//
//  Covers the pure, authorization-free parts of §5.7: the per-card notification
//  request — title-only content, stable identifier, and a trigger that fires at
//  the unlock instant (the chosen local date and time) — and the guards that
//  produce no request when there's nothing to remind about. Constructing UN*
//  objects needs no permission, so this runs without prompting.
//

import Testing
import Foundation
import UserNotifications
@testable import DearFutureMe

@MainActor
struct NotificationSchedulerTests {

    private func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    // MARK: - Request content

    @Test func requestReferencesTheTitleAndLeaksNoContents() throws {
        let cal = calendar("America/New_York")
        let unlock = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        let card = Postcard(title: "Iceland", unlockDate: unlock, state: .sealed)

        let request = try #require(NotificationScheduler.makeRequest(for: card, calendar: cal))

        #expect(request.identifier == "unlock-\(card.id.uuidString)")
        #expect(request.content.title == "Iceland")                 // references the title (§5.3.2)
        #expect(request.content.body == NotificationScheduler.notificationBody)  // fixed, content-free (§5.4)
        #expect(request.content.userInfo["cardID"] as? String == card.id.uuidString)
    }

    @Test func untitledCardFallsBackToANeutralTitle() throws {
        let card = Postcard(title: "   ", unlockDate: Date(timeIntervalSinceReferenceDate: 0), state: .sealed)
        let request = try #require(NotificationScheduler.makeRequest(for: card, calendar: .current))

        #expect(request.content.title == "A postcard")
        #expect(request.content.body == NotificationScheduler.notificationBody)
    }

    // MARK: - Trigger timing

    @Test func triggerFollowsTheUnlockInstant() throws {
        let cal = calendar("America/New_York")
        let unlock = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 14, minute: 30))!
        let card = Postcard(title: "x", unlockDate: unlock, state: .sealed)

        let request = try #require(NotificationScheduler.makeRequest(for: card, calendar: cal))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)

        #expect(trigger.dateComponents.year == 2026)
        #expect(trigger.dateComponents.month == 9)
        #expect(trigger.dateComponents.day == 1)
        #expect(trigger.dateComponents.hour == 14)
        #expect(trigger.dateComponents.minute == 30)
        #expect(trigger.repeats == false)
    }

    @Test func triggerComponentsMirrorTheUnlockTimeAcrossZones() {
        // The trigger fires at the chosen local date+time — no forcing to 9am.
        let cal = calendar("Asia/Tokyo")
        let unlock = cal.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 15, minute: 30))!

        let components = NotificationScheduler.triggerComponents(unlockDate: unlock, calendar: cal)

        #expect(components.hour == 15 && components.minute == 30)
        #expect(components.year == 2027 && components.month == 3 && components.day == 14)
    }

    // MARK: - Nothing to remind about

    @Test func noRequestForDraftUnlockedOrDatelessCards() {
        let draft = Postcard(state: .draft)
        let unlocked = Postcard(unlockDate: Date(timeIntervalSinceReferenceDate: 0), state: .unlocked)
        let sealedNoDate = Postcard(state: .sealed)     // sealed but unlockDate nil

        #expect(NotificationScheduler.makeRequest(for: draft, calendar: .current) == nil)
        #expect(NotificationScheduler.makeRequest(for: unlocked, calendar: .current) == nil)
        #expect(NotificationScheduler.makeRequest(for: sealedNoDate, calendar: .current) == nil)
    }

    // MARK: - Identifier

    @Test func identifierIsStableAndCardScoped() {
        let id = UUID()
        #expect(NotificationScheduler.identifier(for: id) == "unlock-\(id.uuidString)")
    }
}
