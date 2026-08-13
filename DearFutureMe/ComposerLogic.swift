//
//  ComposerLogic.swift
//  DearFutureMe
//
//  The composer's pure, testable core — the two bits of logic worth pinning
//  down with unit tests, kept out of the SwiftUI view (which, per §8, gets no
//  UI tests). The limits, the "9:00am local on the chosen day" rule, and the
//  seal-error copy live here.
//

import Foundation

enum ComposerLogic {

    /// §5.1 field limits, enforced in the composer (the schema doesn't).
    static let maxTitleLength = 60
    static let maxMessageLength = 2_000
    static let maxPhotos = 10

    /// The unlock instant for a chosen day: **09:00 local time** on that
    /// calendar day (task-C / §5.7: notifications deliver at 9am in the user's
    /// current zone, so the unlock instant and the notification align). A `Date`
    /// is an absolute instant, so this is stored UTC automatically (§5.3) — the
    /// 9am is interpreted in `calendar.timeZone` at construction and frozen.
    ///
    /// Only the day of `date` is used; its time-of-day is discarded. `calendar`
    /// is injected so the rule is testable across time zones and DST.
    static func unlockInstant(onDayOf date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    /// Plain, blame-free copy for each seal rejection (§7.2 tone). One line the
    /// composer can show verbatim; distinct per case so the user knows what to do.
    static func sealErrorCopy(_ error: PostcardLifecycle.SealError) -> String {
        switch error {
        case .notADraft:
            return "This postcard has already been sealed."
        case .unlockDateNotInFuture:
            return "Choose a day in the future."
        case .trustedTimeUnavailable:
            return "Can’t reach a trusted clock. Connect to the internet and try again."
        }
    }
}
