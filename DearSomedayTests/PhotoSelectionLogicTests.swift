//
//  PhotoSelectionLogicTests.swift
//  DearSomedayTests
//

import Testing
import Foundation
@testable import DearSomeday

struct PhotoSelectionLogicTests {

    @Test func duplicateIdentifiersAreSkipped() {
        let selectedIdentifiers: Set<String> = ["asset-1"]

        #expect(!PhotoSelectionLogic.canAdd(
            identifier: "asset-1",
            selectedIdentifiers: selectedIdentifiers
        ))
        #expect(PhotoSelectionLogic.canAdd(
            identifier: "asset-2",
            selectedIdentifiers: selectedIdentifiers
        ))
        #expect(PhotoSelectionLogic.canAdd(
            identifier: nil,
            selectedIdentifiers: selectedIdentifiers
        ))
    }

    @Test func removingPhotoReleasesIdentifier() {
        let selected = PhotoSelectionLogic.identifiers(afterAdding: "asset-1", to: [])
        let removed = PhotoSelectionLogic.identifiers(afterRemoving: "asset-1", from: selected)

        #expect(!removed.contains("asset-1"))
        #expect(PhotoSelectionLogic.canAdd(identifier: "asset-1", selectedIdentifiers: removed))
    }

    @Test func duplicateFingerprintsAreSkipped() {
        let fingerprint = PhotoSelectionLogic.fingerprint(for: Data([1, 2, 3]))
        let selected = PhotoSelectionLogic.fingerprints(afterAdding: fingerprint, to: [])

        #expect(!PhotoSelectionLogic.canAdd(
            fingerprint: fingerprint,
            selectedFingerprints: selected
        ))
    }

    @Test func removingPhotoReleasesFingerprint() {
        let fingerprint = PhotoSelectionLogic.fingerprint(for: Data([1, 2, 3]))
        let selected = PhotoSelectionLogic.fingerprints(afterAdding: fingerprint, to: [])
        let removed = PhotoSelectionLogic.fingerprints(afterRemoving: fingerprint, from: selected)

        #expect(!removed.contains(fingerprint))
        #expect(PhotoSelectionLogic.canAdd(
            fingerprint: fingerprint,
            selectedFingerprints: removed
        ))
    }

    @Test func selectedIdentifierInsertionKeepsExistingIdentifiers() {
        let selected = PhotoSelectionLogic.identifiers(afterAdding: "asset-2", to: ["asset-1"])

        #expect(selected == ["asset-1", "asset-2"])
    }

    @Test func maxPhotoCountRemainsSix() {
        #expect(ComposerLogic.maxPhotos == 6)
    }
}
