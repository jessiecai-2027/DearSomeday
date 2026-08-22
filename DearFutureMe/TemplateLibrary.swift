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
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 1),
        ]),
        CardTemplate(id: "two-vertical", name: "Two Vertical", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 1),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 1),
        ]),
        CardTemplate(id: "two-horizontal", name: "Two Stacked", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 0.5),
            TemplateSlot(id: "b", x: 0, y: 0.5, width: 1, height: 0.5),
        ]),
        CardTemplate(id: "three-rows", name: "Three Rows", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 1.0 / 3.0),
            TemplateSlot(id: "b", x: 0, y: 1.0 / 3.0, width: 1, height: 1.0 / 3.0),
            TemplateSlot(id: "c", x: 0, y: 2.0 / 3.0, width: 1, height: 1.0 / 3.0),
        ]),
        CardTemplate(id: "three-top-hero", name: "Top Hero", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 0.5),
            TemplateSlot(id: "b", x: 0, y: 0.5, width: 0.5, height: 0.5),
            TemplateSlot(id: "c", x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ]),
        CardTemplate(id: "three-bottom-hero", name: "Bottom Hero", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 0.5),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 0.5),
            TemplateSlot(id: "c", x: 0, y: 0.5, width: 1, height: 0.5),
        ]),
        CardTemplate(id: "four-rows", name: "Four Rows", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 0.25),
            TemplateSlot(id: "b", x: 0, y: 0.25, width: 1, height: 0.25),
            TemplateSlot(id: "c", x: 0, y: 0.5, width: 1, height: 0.25),
            TemplateSlot(id: "d", x: 0, y: 0.75, width: 1, height: 0.25),
        ]),
        CardTemplate(id: "four-grid", name: "Four Grid", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 0.5),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 0.5),
            TemplateSlot(id: "c", x: 0, y: 0.5, width: 0.5, height: 0.5),
            TemplateSlot(id: "d", x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ]),
        CardTemplate(id: "five-bottom-hero", name: "Bottom Hero Five", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "c", x: 0, y: 1.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "d", x: 0.5, y: 1.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "e", x: 0, y: 2.0 / 3.0, width: 1, height: 1.0 / 3.0),
        ]),
        CardTemplate(id: "five-left-hero", name: "Left Hero Five", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 2.0 / 3.0),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "c", x: 0.5, y: 1.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "d", x: 0, y: 2.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "e", x: 0.5, y: 2.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
        ]),
        CardTemplate(id: "five-right-hero", name: "Right Hero Five", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 2.0 / 3.0),
            TemplateSlot(id: "c", x: 0, y: 1.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "d", x: 0, y: 2.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "e", x: 0.5, y: 2.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
        ]),
        CardTemplate(id: "five-middle-hero", name: "Middle Hero Five", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 0.25),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 0.25),
            TemplateSlot(id: "c", x: 0, y: 0.25, width: 1, height: 0.5),
            TemplateSlot(id: "d", x: 0, y: 0.75, width: 0.5, height: 0.25),
            TemplateSlot(id: "e", x: 0.5, y: 0.75, width: 0.5, height: 0.25),
        ]),
        CardTemplate(id: "six-grid", name: "Six Grid", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "b", x: 0.5, y: 0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "c", x: 0, y: 1.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "d", x: 0.5, y: 1.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "e", x: 0, y: 2.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
            TemplateSlot(id: "f", x: 0.5, y: 2.0 / 3.0, width: 0.5, height: 1.0 / 3.0),
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
