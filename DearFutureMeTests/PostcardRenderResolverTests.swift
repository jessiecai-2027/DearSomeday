//
//  PostcardRenderResolverTests.swift
//  DearFutureMeTests
//

import Testing
import Foundation
import UIKit
@testable import DearFutureMe

@MainActor
struct PostcardRenderResolverTests {

    @Test func resolvesSavedTemplateID() {
        let one = CardTemplate(id: "one", name: "One", slots: [
            TemplateSlot(id: "a", width: 1, height: 1),
        ])
        let two = CardTemplate(id: "two", name: "Two", slots: [
            TemplateSlot(id: "a", width: 0.5, height: 1),
            TemplateSlot(id: "b", x: 0.5, width: 0.5, height: 1),
        ])
        let card = Postcard(templateId: "two", state: .unlocked)

        #expect(PostcardRenderResolver.template(for: card, catalog: [one, two]).id == "two")
    }

    @Test func fallsBackToMatchingPhotoCountWhenTemplateIsMissing() {
        let one = CardTemplate(id: "one", name: "One", slots: [
            TemplateSlot(id: "a", width: 1, height: 1),
        ])
        let two = CardTemplate(id: "two", name: "Two", slots: [
            TemplateSlot(id: "a", width: 0.5, height: 1),
            TemplateSlot(id: "b", x: 0.5, width: 0.5, height: 1),
        ])
        let card = Postcard(
            photos: [
                StoredPhoto(order: 0),
                StoredPhoto(order: 1),
            ],
            templateId: "gone",
            state: .unlocked
        )

        #expect(PostcardRenderResolver.template(for: card, catalog: [one, two]).id == "two")
    }

    @Test func fallsBackToFullFrameWhenNoCatalogTemplateMatches() {
        let two = CardTemplate(id: "two", name: "Two", slots: [
            TemplateSlot(id: "a", width: 0.5, height: 1),
            TemplateSlot(id: "b", x: 0.5, width: 0.5, height: 1),
        ])
        let card = Postcard(photos: [StoredPhoto(order: 0)], state: .unlocked)

        let template = PostcardRenderResolver.template(for: card, catalog: [two])

        #expect(template.slotCount == 1)
        #expect(template.slots[0].width == 1)
        #expect(template.slots[0].height == 1)
    }

    @Test func keepsCompleteValidAssignments() {
        let photoA = UUID()
        let photoB = UUID()
        let assignmentA = SlotAssignment(slotID: "a", photoID: photoA, crop: PhotoCrop(scale: 1.3))
        let assignmentB = SlotAssignment(slotID: "b", photoID: photoB, crop: PhotoCrop(offsetX: 0.1))
        let template = CardTemplate(id: "two", name: "Two", slots: [
            TemplateSlot(id: "a", width: 0.5, height: 1),
            TemplateSlot(id: "b", x: 0.5, width: 0.5, height: 1),
        ])
        let card = Postcard(
            photos: [
                StoredPhoto(id: photoA, order: 0, aspect: 1),
                StoredPhoto(id: photoB, order: 1, aspect: 1),
            ],
            slotAssignments: [assignmentA, assignmentB],
            state: .unlocked
        )

        #expect(PostcardRenderResolver.assignments(for: card, template: template) == [assignmentA, assignmentB])
    }

    @Test func rebuildsAssignmentsWhenSavedAssignmentsAreIncomplete() {
        let photoA = UUID()
        let photoB = UUID()
        let template = CardTemplate(id: "two", name: "Two", slots: [
            TemplateSlot(id: "a", width: 0.5, height: 1),
            TemplateSlot(id: "b", x: 0.5, width: 0.5, height: 1),
        ])
        let card = Postcard(
            photos: [
                StoredPhoto(id: photoA, order: 0, aspect: 1),
                StoredPhoto(id: photoB, order: 1, aspect: 1),
            ],
            slotAssignments: [SlotAssignment(slotID: "a", photoID: photoA)],
            state: .unlocked
        )

        let assignments = PostcardRenderResolver.assignments(for: card, template: template)

        #expect(assignments.count == 2)
        #expect(Set(assignments.map(\.slotID)) == ["a", "b"])
        #expect(Set(assignments.map(\.photoID)) == [photoA, photoB])
    }

    @Test func resolvesFontAndColorFallbacks() {
        let card = Postcard(
            backFontId: "unknown",
            backTextColorHex: "not-a-color",
            state: .unlocked
        )

        #expect(PostcardRenderResolver.backFont(for: card) == .defaultFont)
        #expect(PostcardRenderResolver.backTextColorHex(for: card) == PostcardBackTextColor.defaultColor.hex)
        #expect(PostcardBackTextColor.resolvedHex("a46150") == "#A46150")
    }

    @Test func resolvesPersistedFontSizeAndTreatsMissingOrInvalidSizesAsLegacy() {
        let saved = Postcard(backFontPointSize: 14.5, state: .unlocked)
        let legacy = Postcard(backFontPointSize: nil, state: .unlocked)
        let invalid = Postcard(backFontPointSize: 4, state: .unlocked)

        #expect(PostcardRenderResolver.backFontPointSize(for: saved) == 14.5)
        #expect(PostcardRenderResolver.backFontPointSize(for: legacy) == nil)
        #expect(PostcardRenderResolver.backFontPointSize(for: invalid) == nil)
    }

    @Test func resolvesKnownStampAndIgnoresLegacyOrUnknownStampData() {
        let known = Postcard(
            decorationElements: [CanvasElement(kind: .stamp, assetId: "robin")]
        )
        let legacy = Postcard()
        let unknown = Postcard(
            decorationElements: [CanvasElement(kind: .stamp, assetId: "retired-stamp")]
        )

        #expect(PostcardRenderResolver.stamp(for: known)?.id == "robin")
        #expect(PostcardRenderResolver.stamp(for: legacy) == nil)
        #expect(PostcardRenderResolver.stamp(for: unknown) == nil)
    }

    @Test func stampCatalogHasSevenUniqueStableIDsAndLoadableImages() throws {
        #expect(StampCatalog.all.count == 7)
        #expect(Set(StampCatalog.all.map(\.id)).count == StampCatalog.all.count)

        for option in StampCatalog.all {
            let image = try #require(UIImage(named: option.imageName))
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
            let alpha = try #require(image.cgImage).alphaInfo
            #expect(alpha != .none)
            #expect(alpha != .noneSkipFirst)
            #expect(alpha != .noneSkipLast)
        }
    }

    @Test func everyStampAspectFitsInsideThePrintedBoxWithoutCropping() throws {
        let box = PostcardBackLayout.stampFrame(in: CGSize(width: 320, height: 480))

        for option in StampCatalog.all {
            let image = try #require(UIImage(named: option.imageName))
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)

            #expect(fitted.width <= box.width + 0.001)
            #expect(fitted.height <= box.height + 0.001)
        }
    }

    @Test func stampFrameUsesTheSharedNormalizedGeometry() {
        let size = CGSize(width: 320, height: 480)
        let frame = PostcardBackLayout.stampFrame(in: size)

        #expect(frame.origin.x == size.width * 0.706)
        #expect(frame.origin.y == size.height * 0.064)
        #expect(frame.width == size.width * 0.183)
        #expect(frame.height == size.height * 0.119)
    }
}
