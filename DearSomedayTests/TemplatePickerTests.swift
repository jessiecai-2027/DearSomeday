//
//  TemplatePickerTests.swift
//  DearSomedayTests
//

import Testing
import Foundation
import CoreGraphics
@testable import DearSomeday

@MainActor
struct TemplatePickerTests {

    @Test func rankedReturnsOnlyExactPhotoCountMatches() {
        let one = CardTemplate(id: "one", name: "One", slots: [
            TemplateSlot(id: "a", width: 1, height: 1),
        ])
        let two = CardTemplate(id: "two", name: "Two", slots: [
            TemplateSlot(id: "a", width: 1, height: 1),
            TemplateSlot(id: "b", width: 1, height: 1),
        ])

        let ranked = TemplatePicker.ranked([one, two], photoAspects: [1, 1])

        #expect(ranked.map(\.id) == ["two"])
    }

    @Test func templateCatalogCoversOneThroughSixPhotos() {
        for count in 1...6 {
            let matches = TemplatePicker.ranked(
                TemplatePicker.all,
                photoAspects: Array(repeating: 1, count: count)
            )

            #expect(!matches.isEmpty)
            #expect(matches.allSatisfy { $0.slotCount == count })
        }
    }

    @Test func templateSlotsStayInsidePostcardBounds() {
        for template in TemplatePicker.all {
            for slot in template.slots {
                #expect(slot.x >= 0)
                #expect(slot.y >= 0)
                #expect(slot.width > 0)
                #expect(slot.height > 0)
                #expect(slot.x + slot.width <= 1)
                #expect(slot.y + slot.height <= 1)
            }
        }
    }

    @Test func rankedPrefersBetterAspectFit() {
        let wide = CardTemplate(id: "wide", name: "Wide", slots: [
            TemplateSlot(id: "a", width: 0.8, height: 0.4),
        ])
        let tall = CardTemplate(id: "tall", name: "Tall", slots: [
            TemplateSlot(id: "a", width: 0.4, height: 0.8),
        ])

        let ranked = TemplatePicker.ranked([tall, wide], photoAspects: [2])

        #expect(ranked.first?.id == "wide")
    }

    @Test func autoFillPairsWidestPhotosWithWidestSlots() {
        let template = CardTemplate(id: "mixed", name: "Mixed", slots: [
            TemplateSlot(id: "narrow", width: 0.25, height: 0.75),
            TemplateSlot(id: "wide", width: 0.75, height: 0.25),
        ])
        let widePhoto = UUID()
        let tallPhoto = UUID()

        let assignments = template.autoFillMatched(
            photoIDs: [tallPhoto, widePhoto],
            aspects: [widePhoto: 3, tallPhoto: 0.4]
        )

        #expect(assignments.first { $0.slotID == "wide" }?.photoID == widePhoto)
        #expect(assignments.first { $0.slotID == "narrow" }?.photoID == tallPhoto)
    }

    @Test func cropAndAnimationMetadataRoundTripAsCodableValues() throws {
        let photoID = UUID()
        let assignment = SlotAssignment(
            slotID: "slot-a",
            photoID: photoID,
            crop: PhotoCrop(scale: 1.4, offsetX: 0.12, offsetY: -0.2)
        )
        let cue = AnimationCue(targetID: "slot-a", kind: "future-fade", startTime: 0.1, duration: 0.8)
        let card = Postcard(
            photos: [StoredPhoto(id: photoID, order: 0, fileName: "a.jpg", aspect: 1.5)],
            templateId: "template-a",
            slotAssignments: [assignment],
            backText: "hello",
            backFontId: "serif",
            backTextColorHex: "#111111",
            locationLabel: "Kyoto",
            animationMetadata: [cue],
            unlockDate: Date(),
            state: .sealed
        )

        #expect(card.slotAssignments == [assignment])
        #expect(card.animationMetadata == [cue])
        #expect(card.locationLabel == "Kyoto")
    }

    @Test func animationMetadataDefaultsEmpty() {
        let card = Postcard(unlockDate: Date(), state: .sealed)

        #expect(card.animationMetadata.isEmpty)
    }

    @Test func cropOffsetsCannotExposeEmptySpace() {
        let crop = PhotoCrop(scale: 1, offsetX: 10, offsetY: -10)
            .constrained(sourceAspect: 2, targetAspect: 1)

        #expect(crop.offsetX == 0.5)
        #expect(crop.offsetY == 0)
    }

    @Test func cropOffsetsExpandAndReclampWithZoom() {
        let zoomed = PhotoCrop(scale: 2, offsetX: 10, offsetY: -10)
            .constrained(sourceAspect: 0.5, targetAspect: 1)

        #expect(zoomed.offsetX == 0.5)
        #expect(zoomed.offsetY == -1.5)

        let zoomedOut = PhotoCrop(scale: 1, offsetX: zoomed.offsetX, offsetY: zoomed.offsetY)
            .constrained(sourceAspect: 0.5, targetAspect: 1)

        #expect(zoomedOut.offsetX == 0)
        #expect(zoomedOut.offsetY == -0.5)
    }

    @Test func renderedSlotAspectsMatchTheirFramesInThePostcardCanvas() {
        let canvasSize = CGSize(width: 300, height: 450)

        for template in TemplatePicker.all {
            for slot in template.slots {
                let frameWidth = CGFloat(slot.width) * canvasSize.width
                let frameHeight = CGFloat(slot.height) * canvasSize.height
                let frameAspect = frameWidth / frameHeight

                #expect(abs(slot.renderedAspect() - frameAspect) < 0.000_001)
            }
        }
    }

    @Test func everyTemplateCropConstraintKeepsEverySlotCovered() {
        let sourceAspects: [CGFloat] = [0.4, 1, 2.5]
        let scales: [Double] = [1, 1.75, 4]
        let extremeOffsets: [(Double, Double)] = [
            (-100, -100),
            (-100, 100),
            (100, -100),
            (100, 100),
        ]

        for template in TemplatePicker.all {
            for slot in template.slots {
                let targetAspect = slot.renderedAspect()

                for sourceAspect in sourceAspects {
                    for scale in scales {
                        for (offsetX, offsetY) in extremeOffsets {
                            let crop = PhotoCrop(scale: scale, offsetX: offsetX, offsetY: offsetY)
                                .constrained(sourceAspect: sourceAspect, targetAspect: targetAspect)
                            let sourceToTarget = Double(sourceAspect / targetAspect)
                            let renderedWidth = crop.scale * max(1, sourceToTarget)
                            let renderedHeight = crop.scale * max(1, 1 / sourceToTarget)

                            #expect(abs(crop.offsetX) + 0.5 <= renderedWidth / 2 + 0.000_001)
                            #expect(abs(crop.offsetY) + 0.5 <= renderedHeight / 2 + 0.000_001)
                        }
                    }
                }
            }
        }
    }

    @Test func stackedAndVerticalTemplatesUsePhysicalSlotAspects() throws {
        let stacked = try #require(TemplatePicker.all.first { $0.id == "two-horizontal" })
        let vertical = try #require(TemplatePicker.all.first { $0.id == "two-vertical" })
        let stackedSlot = try #require(stacked.slots.first)
        let verticalSlot = try #require(vertical.slots.first)

        #expect(abs(stackedSlot.renderedAspect() - 4.0 / 3.0) < 0.000_001)
        #expect(abs(verticalSlot.renderedAspect() - 1.0 / 3.0) < 0.000_001)

        let stackedCrop = PhotoCrop(scale: 1, offsetY: 100)
            .constrained(sourceAspect: 0.75, targetAspect: stackedSlot.renderedAspect())
        #expect(abs(stackedCrop.offsetY - 7.0 / 18.0) < 0.000_001)

        let verticalCrop = PhotoCrop(scale: 1, offsetY: 100)
            .constrained(sourceAspect: 0.46, targetAspect: verticalSlot.renderedAspect())
        #expect(verticalCrop.offsetY == 0)
    }
}
