//
//  PhotoSelectionLogicTests.swift
//  DearFutureMeTests
//

import Testing
@testable import DearFutureMe

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

    @Test func selectedIdentifierInsertionKeepsExistingIdentifiers() {
        let selected = PhotoSelectionLogic.identifiers(afterAdding: "asset-2", to: ["asset-1"])

        #expect(selected == ["asset-1", "asset-2"])
    }

    @Test func maxPhotoCountRemainsSix() {
        #expect(ComposerLogic.maxPhotos == 6)
    }
}
