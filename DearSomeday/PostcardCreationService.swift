//
//  PostcardCreationService.swift
//  DearSomeday
//
//  Owns the create flow's storage side: stage photo derivatives, build a
//  backend-safe postcard payload, seal through trusted lifecycle logic, and
//  persist only through PostcardStore.
//

import Foundation
import CoreGraphics
import UIKit

struct CreationPhoto: Identifiable {
    var id: UUID
    var fileName: String
    var aspect: CGFloat
    var thumbnail: UIImage?
    var sourceIdentifier: String?
    var sourceFingerprint: String?
}

struct PostcardCreationInput {
    var title: String
    var photos: [CreationPhoto]
    var template: CardTemplate
    var assignments: [SlotAssignment]
    var backText: String
    var backFontId: String?
    var backFontPointSize: Double? = nil
    var backTextColorHex: String
    var stampAssetID: String? = nil
    var locationLabel: String?
    var unlockDate: Date
}

enum PostcardCreationError: Error, Equatable {
    case noPhotos
    case missingAssignments
    case missingStamp
    case unknownStamp
    case trustedTimeUnavailable
}

@MainActor
final class PostcardCreationService {

    private let store: PostcardStore
    private let photoStore: PhotoStore
    private let lifecycle: PostcardLifecycle
    private let clock: TrustedClock

    init(
        store: PostcardStore,
        photoStore: PhotoStore,
        lifecycle: PostcardLifecycle,
        clock: TrustedClock
    ) {
        self.store = store
        self.photoStore = photoStore
        self.lifecycle = lifecycle
        self.clock = clock
    }

    func importPhoto(
        _ image: UIImage,
        sourceIdentifier: String? = nil,
        sourceFingerprint: String? = nil
    ) throws -> CreationPhoto {
        let saved = try photoStore.saveDerivative(image)
        let thumb = photoStore.loadData(fileName: saved.fileName).flatMap(UIImage.init(data:))
        return CreationPhoto(
            id: UUID(),
            fileName: saved.fileName,
            aspect: saved.aspect,
            thumbnail: thumb,
            sourceIdentifier: sourceIdentifier,
            sourceFingerprint: sourceFingerprint
        )
    }

    func discard(_ photos: [CreationPhoto]) {
        photoStore.delete(fileNames: photos.map(\.fileName))
    }

    func create(_ input: PostcardCreationInput) async throws -> Postcard {
        guard !input.photos.isEmpty else { throw PostcardCreationError.noPhotos }
        guard input.assignments.count == input.template.slotCount else {
            throw PostcardCreationError.missingAssignments
        }
        guard let stampAssetID = input.stampAssetID else {
            throw PostcardCreationError.missingStamp
        }
        guard StampCatalog.option(withID: stampAssetID) != nil else {
            throw PostcardCreationError.unknownStamp
        }

        if case .neverSynced = clock.now() {
            await clock.refresh()
        }
        guard case .trusted(let now) = clock.now() else {
            throw PostcardCreationError.trustedTimeUnavailable
        }

        let storedPhotos = input.photos.enumerated().map { index, photo in
            StoredPhoto(
                id: photo.id,
                order: index,
                fileName: photo.fileName,
                aspect: Double(photo.aspect)
            )
        }
        let photosByID = Dictionary(uniqueKeysWithValues: input.photos.map { ($0.id, $0) })
        let slotsByID = Dictionary(uniqueKeysWithValues: input.template.slots.map { ($0.id, $0) })
        let constrainedAssignments = input.assignments.map { assignment in
            guard let photo = photosByID[assignment.photoID],
                  let slot = slotsByID[assignment.slotID]
            else { return assignment }

            var constrained = assignment
            constrained.crop = assignment.crop.constrained(
                sourceAspect: photo.aspect,
                targetAspect: slot.renderedAspect()
            )
            return constrained
        }
        let backText = input.backText.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = input.locationLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stampFrame = PostcardBackLayout.normalizedStampFrame
        let stampElement = CanvasElement(
            kind: .stamp,
            assetId: stampAssetID,
            x: stampFrame.midX,
            y: stampFrame.midY,
            rotation: 0,
            scale: 1,
            zIndex: 0
        )
        let draft = Postcard(
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            message: backText,
            photos: storedPhotos,
            templateId: input.template.id,
            slotAssignments: constrainedAssignments,
            backText: backText,
            backFontId: input.backFontId,
            backFontPointSize: input.backFontPointSize,
            backTextColorHex: input.backTextColorHex,
            locationLabel: location?.isEmpty == true ? nil : location,
            animationMetadata: [],
            createdAt: now,
            state: .draft,
            decorationElements: [stampElement]
        )

        do {
            try lifecycle.seal(draft, unlockDate: input.unlockDate)
            try await store.create(draft)
            return draft
        } catch {
            discard(input.photos)
            throw error
        }
    }
}
