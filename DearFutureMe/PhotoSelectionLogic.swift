//
//  PhotoSelectionLogic.swift
//  DearFutureMe
//
//  Pure bookkeeping for the composer's photo-selection step.
//

import Foundation

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
}
