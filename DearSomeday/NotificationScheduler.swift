//
//  NotificationScheduler.swift
//  DearSomeday
//
//  Local unlock notifications (§5.7). Three collaborators:
//   • NotificationScheduler — requests permission, and (re)schedules one local
//     notification per sealed card at its unlock instant (the chosen local
//     date and time).
//   • NotificationRouter    — a tiny observable the delegate writes a tapped
//     card id into; the timeline consumes it and routes to the display view.
//   • NotificationDelegate  — receives taps and foreground presentations.
//
//  ── Why re-scan and re-schedule every launch (§5.7) ────────────────────────
//  Uninstalling wipes the pending-notification queue. A reinstall from device
//  backup restores the cards but NOT their notifications, so nothing would ever
//  fire again. So on every launch/foreground we clear our pending requests and
//  rebuild them from `sealedPostcards()` — the whole reason that unpaginated
//  fetch exists.
//
//  ── Why the notification carries the title at most (§5.4) ───────────────────
//  iOS fires local notifications on DEVICE time, which a user can spoof forward.
//  So a fired notification is not proof a card is truly unlocked. The body is a
//  fixed, content-free string and only the title is surfaced (title is allowed
//  visible pre-unlock, §5.3.2). Tapping routes through the display view, which
//  re-verifies against trusted time before revealing anything — the notification
//  is never a shortcut to contents.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler {

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Requests permission. Called only after the first seal's priming (§7.1),
    /// never at launch. Returns whether it was granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - (Re)scheduling — §5.7

    /// Clears our pending unlock notifications and, if authorized, schedules one
    /// per sealed card. Safe to call every launch/foreground.
    func reschedule(for sealedCards: [Postcard]) async {
        center.removeAllPendingNotificationRequests()
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        for card in sealedCards {
            guard let request = Self.makeRequest(for: card, calendar: .current) else { continue }
            try? await center.add(request)
        }
    }

    /// Drops a single card's pending notification (e.g. on delete), so a fired
    /// reminder can't outlive the card within a session.
    func removePending(cardID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: cardID)])
    }

    // MARK: - Pure builders (testable without authorization)

    static func identifier(for cardID: UUID) -> String {
        "unlock-\(cardID.uuidString)"
    }

    /// The notification's title line references the postcard's title (allowed
    /// visible pre-unlock, §5.3.2), with a neutral fallback for untitled cards.
    static func notificationTitle(forCardTitle title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "A postcard" : trimmed
    }

    /// Fixed, content-free body — no photos, no message (§5.4).
    static let notificationBody = "It’s ready to open."

    /// The unlock instant's wall-clock components (minute precision) in the given
    /// zone, so the notification fires at the chosen local date and time (§5.7).
    /// Rebuilt each reschedule, so a timezone change since sealing is picked up
    /// on the next launch.
    static func triggerComponents(unlockDate: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: unlockDate)
    }

    /// A request for a sealed card, or nil if there's nothing to remind about
    /// (not sealed, or no unlock date).
    static func makeRequest(for card: Postcard, calendar: Calendar) -> UNNotificationRequest? {
        guard card.state == .sealed, let unlockDate = card.unlockDate else { return nil }

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(forCardTitle: card.title)
        content.body = notificationBody
        content.userInfo = ["cardID": card.id.uuidString]
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents(unlockDate: unlockDate, calendar: calendar),
            repeats: false
        )
        return UNNotificationRequest(
            identifier: identifier(for: card.id),
            content: content,
            trigger: trigger
        )
    }
}

// MARK: - Tap routing

/// The seam between the (nonisolated) notification delegate and SwiftUI. The
/// delegate sets `pendingCardID` on a tap; the timeline observes it, routes to
/// the display view (which re-verifies), then clears it.
@MainActor
@Observable
final class NotificationRouter {
    var pendingCardID: UUID?
}

/// Handles notification taps and foreground presentation. `nonisolated` (like
/// the other IO types) so it satisfies `UNUserNotificationCenterDelegate`
/// cleanly; it hops to the main actor only to write the router.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let router: NotificationRouter

    init(router: NotificationRouter) {
        self.router = router
    }

    /// A tap: hand the card id to the router. Routing (and the §5.4 re-verify)
    /// happens in the display view, never here.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["cardID"] as? String, let id = UUID(uuidString: raw) else { return }
        await MainActor.run { router.pendingCardID = id }
    }

    /// Show the banner even when the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
