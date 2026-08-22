//
//  TemplateLibrary.swift
//  DearFutureMe
//
//  Backend-agnostic front-side postcard templates plus the ranking logic from
//  the attached TemplateRanking.swift.
//

import Foundation
import CoreGraphics

enum TemplatePicker {

    static let all: [CardTemplate] = [
        CardTemplate(id: "one-full", name: "Full Frame", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.84, height: 0.84),
        ]),
        CardTemplate(id: "two-stacked", name: "Stacked", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.84, height: 0.40),
            TemplateSlot(id: "b", x: 0.08, y: 0.52, width: 0.84, height: 0.40),
        ]),
        CardTemplate(id: "two-side-by-side", name: "Side by Side", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.40, height: 0.84),
            TemplateSlot(id: "b", x: 0.52, y: 0.08, width: 0.40, height: 0.84),
        ]),
        CardTemplate(id: "three-hero", name: "Hero Trio", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.84, height: 0.52),
            TemplateSlot(id: "b", x: 0.08, y: 0.64, width: 0.40, height: 0.28),
            TemplateSlot(id: "c", x: 0.52, y: 0.64, width: 0.40, height: 0.28),
        ]),
        CardTemplate(id: "three-column", name: "Three Strip", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.25, height: 0.84),
            TemplateSlot(id: "b", x: 0.375, y: 0.08, width: 0.25, height: 0.84),
            TemplateSlot(id: "c", x: 0.67, y: 0.08, width: 0.25, height: 0.84),
        ]),
        CardTemplate(id: "four-grid", name: "Four Grid", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.40, height: 0.40),
            TemplateSlot(id: "b", x: 0.52, y: 0.08, width: 0.40, height: 0.40),
            TemplateSlot(id: "c", x: 0.08, y: 0.52, width: 0.40, height: 0.40),
            TemplateSlot(id: "d", x: 0.52, y: 0.52, width: 0.40, height: 0.40),
        ]),
        CardTemplate(id: "five-mosaic", name: "Mosaic Five", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.52, height: 0.52),
            TemplateSlot(id: "b", x: 0.64, y: 0.08, width: 0.28, height: 0.24),
            TemplateSlot(id: "c", x: 0.64, y: 0.36, width: 0.28, height: 0.24),
            TemplateSlot(id: "d", x: 0.08, y: 0.64, width: 0.40, height: 0.28),
            TemplateSlot(id: "e", x: 0.52, y: 0.64, width: 0.40, height: 0.28),
        ]),
        CardTemplate(id: "six-grid", name: "Six Grid", slots: [
            TemplateSlot(id: "a", x: 0.08, y: 0.08, width: 0.25, height: 0.40),
            TemplateSlot(id: "b", x: 0.375, y: 0.08, width: 0.25, height: 0.40),
            TemplateSlot(id: "c", x: 0.67, y: 0.08, width: 0.25, height: 0.40),
            TemplateSlot(id: "d", x: 0.08, y: 0.52, width: 0.25, height: 0.40),
            TemplateSlot(id: "e", x: 0.375, y: 0.52, width: 0.25, height: 0.40),
            TemplateSlot(id: "f", x: 0.67, y: 0.52, width: 0.25, height: 0.40),
        ]),
    ]

    /// Only templates whose slot count exactly matches the number of photos.
    static func ranked(
        _ templates: [CardTemplate],
        photoAspects: [CGFloat]
    ) -> [CardTemplate] {
        templates
            .filter { $0.slotCount == photoAspects.count }
            .sorted { $0.fit(photoAspects: photoAspects) > $1.fit(photoAspects: photoAspects) }
    }
}

extension CardTemplate {

    /// How well this template suits a given set of photos. 0-1, where 1 means
    /// every photo drops straight into a slot with no cropping.
    func fit(photoAspects: [CGFloat]) -> Double {
        guard photoAspects.count >= slotCount, slotCount > 0 else { return 0 }

        let photos = photoAspects.sorted(by: >).prefix(slotCount)
        let ordered = slots.sorted { $0.aspect > $1.aspect }

        let retained = zip(ordered, photos).map { slot, photo -> Double in
            let s = Double(slot.aspect), p = Double(photo)
            return s > p ? p / s : s / p
        }
        return retained.reduce(0, +) / Double(retained.count)
    }

    /// Auto-fill by aspect match rather than selection order.
    func autoFillMatched(photoIDs: [UUID], aspects: [UUID: CGFloat]) -> [SlotAssignment] {
        let sortedPhotos = photoIDs
            .sorted { (aspects[$0] ?? 1) > (aspects[$1] ?? 1) }
            .prefix(slotCount)

        let sortedSlots = slots.sorted { $0.aspect > $1.aspect }

        return zip(sortedSlots, sortedPhotos).map { slot, photoID in
            SlotAssignment(
                slotID: slot.id,
                photoID: photoID,
                crop: .centred(source: aspects[photoID] ?? 1, target: slot.aspect)
            )
        }
    }
}
