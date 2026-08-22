//
//  PhotoSelectionLogic.swift
//  DearFutureMe
//
//  Pure bookkeeping for the composer's photo-selection step.
//

import Foundation
import CryptoKit

enum PhotoSelectionLogic {

    static func canAdd(identifier: String?, selectedIdentifiers: Set<String>) -> Bool {
        guard let identifier else { return true }
        return !selectedIdentifiers.contains(identifier)
    }

    static func identifiers(afterAdding identifier: String?, to selectedIdentifiers: Set<String>) -> Set<String> {
        guard let identifier else { return selectedIdentifiers }
        var next = selectedIdentifiers
        next.insert(identifier)
        return next
    }

    static func identifiers(afterRemoving identifier: String?, from selectedIdentifiers: Set<String>) -> Set<String> {
        guard let identifier else { return selectedIdentifiers }
        var next = selectedIdentifiers
        next.remove(identifier)
        return next
    }

    static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func canAdd(fingerprint: String, selectedFingerprints: Set<String>) -> Bool {
        !selectedFingerprints.contains(fingerprint)
    }

    static func fingerprints(afterAdding fingerprint: String, to selectedFingerprints: Set<String>) -> Set<String> {
        var next = selectedFingerprints
        next.insert(fingerprint)
        return next
    }

    static func fingerprints(afterRemoving fingerprint: String?, from selectedFingerprints: Set<String>) -> Set<String> {
        guard let fingerprint else { return selectedFingerprints }
        var next = selectedFingerprints
        next.remove(fingerprint)
        return next
    }
}
