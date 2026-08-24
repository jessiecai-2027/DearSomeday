//
//  PostcardRenderResolver.swift
//  DearFutureMe
//
//  Pure helpers for turning persisted postcard design data into render-ready
//  values. This keeps legacy fallback behavior out of SwiftUI views.
//

import Foundation
import CoreGraphics

enum PostcardRenderResolver {

    static func template(for card: Postcard, catalog: [CardTemplate] = TemplatePicker.all) -> CardTemplate {
        if let templateId = card.templateId,
           let saved = catalog.first(where: { $0.id == templateId }) {
            return saved
        }

        let photoCount = card.photos.count
        if let exact = catalog.first(where: { $0.slotCount == photoCount }) {
            return exact
        }

        return CardTemplate(id: "legacy-full-frame", name: "Full Frame", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 1),
        ])
    }

    static func assignments(for card: Postcard, template: CardTemplate) -> [SlotAssignment] {
        let photos = card.photos.sorted { $0.order < $1.order }
        let photoIDs = photos.map(\.id)
        let validPhotoIDs = Set(photoIDs)
        let validSlotIDs = Set(template.slots.map(\.id))
        var savedBySlot: [String: SlotAssignment] = [:]
        for assignment in card.slotAssignments where savedBySlot[assignment.slotID] == nil {
            savedBySlot[assignment.slotID] = assignment
        }

        let resolved = template.slots.compactMap { slot -> SlotAssignment? in
            guard let saved = savedBySlot[slot.id],
                  validSlotIDs.contains(saved.slotID),
                  validPhotoIDs.contains(saved.photoID)
            else { return nil }
            return saved
        }

        guard resolved.count == template.slotCount else {
            return template.autoFillMatched(photoIDs: photoIDs, aspects: aspectsByID(for: photos))
        }

        return resolved
    }

    static func backFont(for card: Postcard) -> PostcardBackFont {
        PostcardBackFont.resolved(id: card.backFontId)
    }

    static func backTextColorHex(for card: Postcard) -> String {
        PostcardBackTextColor.resolvedHex(card.backTextColorHex)
    }

    private static func aspectsByID(for photos: [StoredPhoto]) -> [UUID: CGFloat] {
        Dictionary(uniqueKeysWithValues: photos.map { photo in
            (photo.id, CGFloat(photo.aspect))
        })
    }
}
