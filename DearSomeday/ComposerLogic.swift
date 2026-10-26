//
//  ComposerLogic.swift
//  DearSomeday
//
//  The composer's pure, testable core — the two bits of logic worth pinning
//  down with unit tests, kept out of the SwiftUI view (which, per §8, gets no
//  UI tests). The limits, the "chosen local date and time" unlock rule, and the
//  seal-error copy live here.
//

import Foundation

enum ComposerLogic {

    /// §5.1 field limits, enforced in the composer (the schema doesn't).
    static let maxTitleLength = 60
    static let maxMessageLength = 2_000
    static let minPhotos = 1
    static let maxPhotos = 6

    /// The unlock instant from the composer's date **and time** picker: the
    /// chosen local date and time, normalised to minute precision (seconds and
    /// sub-seconds dropped — the picker exposes only hour+minute, and
    /// notifications are minute-granular). A `Date` is an absolute instant, so
    /// this is stored UTC automatically (§5.3); the wall-clock components are
    /// interpreted in `calendar.timeZone` and frozen. `calendar` is injected so
    /// the rule is testable across time zones and DST.
    static func unlockInstant(from date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
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

    static func creationErrorCopy(_ error: PostcardCreationError) -> String {
        switch error {
        case .noPhotos:
            return "Choose at least one photo."
        case .missingAssignments:
            return "Choose a template before sealing."
        case .missingStamp:
            return "Choose a stamp before sealing."
        case .unknownStamp:
            return "That stamp isn’t available. Choose another one."
        case .trustedTimeUnavailable:
            return "Can’t reach a trusted clock. Connect to the internet and try again."
        }
    }
}
