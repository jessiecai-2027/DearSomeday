//
//  PostcardCreationService.swift
//  DearFutureMe
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
    var backTextColorHex: String
    var locationLabel: String?
    var unlockDate: Date
}

enum PostcardCreationError: Error, Equatable {
    case noPhotos
    case missingAssignments
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

        if case .neverSynced = clock.now() {
            await clock.syncFromServer()
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
        let backText = input.backText.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = input.locationLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = Postcard(
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            message: backText,
            photos: storedPhotos,
            templateId: input.template.id,
            slotAssignments: input.assignments,
            backText: backText,
            backFontId: input.backFontId,
            backTextColorHex: input.backTextColorHex,
            locationLabel: location?.isEmpty == true ? nil : location,
            animationMetadata: [],
            createdAt: now,
            state: .draft
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
