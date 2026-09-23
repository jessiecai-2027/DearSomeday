//
//  PostcardCreationServiceTests.swift
//  DearFutureMeTests
//

import Testing
import Foundation
import UIKit
@testable import DearFutureMe

@MainActor
struct PostcardCreationServiceTests {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func solidImage(width: Int = 800, height: Int = 600) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func tempPhotoStore() throws -> FileSystemPhotoStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostcardCreationServiceTests-\(UUID().uuidString)", isDirectory: true)
        return try FileSystemPhotoStore(directory: dir)
    }

    private func makeClock() -> TrustedClock {
        TrustedClock(
            store: InMemoryTrustedTimeStore(),
            uptime: { 100 },
            server: FixedServerClock(now)
        )
    }

    private func service(
        store: PostcardStore,
        photoStore: PhotoStore,
        clock: TrustedClock
    ) -> PostcardCreationService {
        let lifecycle = PostcardLifecycle(clock: clock)
        return PostcardCreationService(
            store: store,
            photoStore: photoStore,
            lifecycle: lifecycle,
            clock: clock
        )
    }

    @Test func createSavesASealedPostcardThroughTheStore() async throws {
        let store = InMemoryPostcardStore()
        let photoStore = try tempPhotoStore()
        let clock = makeClock()
        let service = service(store: store, photoStore: photoStore, clock: clock)
        let photo = try service.importPhoto(solidImage())
        let template = CardTemplate(id: "one", name: "One", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 1),
        ])
        let assignments = template.autoFillMatched(photoIDs: [photo.id], aspects: [photo.id: photo.aspect])

        let card = try await service.create(PostcardCreationInput(
            title: "Future",
            photos: [photo],
            template: template,
            assignments: assignments,
            backText: "remember this",
            backFontId: "serif",
            backFontPointSize: 14.25,
            backTextColorHex: "#111111",
            stampAssetID: "robin",
            locationLabel: "Seattle",
            unlockDate: now.addingTimeInterval(86_400)
        ))

        let stored = try #require(try await store.postcard(withID: card.id))
        #expect(stored.state == .sealed)
        #expect(stored.createdAt == now)
        #expect(stored.templateId == "one")
        #expect(stored.slotAssignments == assignments)
        #expect(stored.backText == "remember this")
        #expect(stored.backFontId == "serif")
        #expect(stored.backFontPointSize == 14.25)
        #expect(stored.backTextColorHex == "#111111")
        #expect(stored.locationLabel == "Seattle")
        #expect(stored.animationMetadata.isEmpty)
        #expect(stored.decorationElements.count == 1)
        let stamp = try #require(stored.decorationElements.first)
        #expect(stamp.kind == .stamp)
        #expect(stamp.assetId == "robin")
        #expect(abs(stamp.x - Double(PostcardBackLayout.normalizedStampFrame.midX)) < 0.000_001)
        #expect(abs(stamp.y - Double(PostcardBackLayout.normalizedStampFrame.midY)) < 0.000_001)
        #expect(photoStore.loadData(fileName: photo.fileName) != nil)
    }

    @Test func createRejectsZeroPhotos() async throws {
        let store = InMemoryPostcardStore()
        let photoStore = try tempPhotoStore()
        let clock = makeClock()
        let service = service(store: store, photoStore: photoStore, clock: clock)
        let template = CardTemplate(id: "empty", name: "Empty")

        await #expect(throws: PostcardCreationError.noPhotos) {
            _ = try await service.create(PostcardCreationInput(
                title: "",
                photos: [],
                template: template,
                assignments: [],
                backText: "",
                backFontId: nil,
                backTextColorHex: "#2B241E",
                stampAssetID: "golden-flower",
                locationLabel: nil,
                unlockDate: now.addingTimeInterval(86_400)
            ))
        }
    }

    @Test func storeFailureCleansUpStagedPhotoBytes() async throws {
        let store = FailingCreateStore()
        let photoStore = try tempPhotoStore()
        let clock = makeClock()
        let service = service(store: store, photoStore: photoStore, clock: clock)
        let photo = try service.importPhoto(solidImage())
        let template = CardTemplate(id: "one", name: "One", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 1),
        ])
        let assignments = template.autoFillMatched(photoIDs: [photo.id], aspects: [photo.id: photo.aspect])

        await #expect(throws: FailingCreateStore.Boom.self) {
            _ = try await service.create(PostcardCreationInput(
                title: "",
                photos: [photo],
                template: template,
                assignments: assignments,
                backText: "",
                backFontId: nil,
                backTextColorHex: "#2B241E",
                stampAssetID: "golden-flower",
                locationLabel: nil,
                unlockDate: now.addingTimeInterval(86_400)
            ))
        }

        #expect(photoStore.loadData(fileName: photo.fileName) == nil)
    }

    @Test func createRejectsMissingAndUnknownStamps() async throws {
        let store = InMemoryPostcardStore()
        let photoStore = try tempPhotoStore()
        let clock = makeClock()
        let service = service(store: store, photoStore: photoStore, clock: clock)
        let photo = try service.importPhoto(solidImage())
        let template = CardTemplate(id: "one", name: "One", slots: [
            TemplateSlot(id: "a", x: 0, y: 0, width: 1, height: 1),
        ])
        let assignments = template.autoFillMatched(photoIDs: [photo.id], aspects: [photo.id: photo.aspect])

        func input(stampAssetID: String?) -> PostcardCreationInput {
            PostcardCreationInput(
                title: "",
                photos: [photo],
                template: template,
                assignments: assignments,
                backText: "",
                backFontId: nil,
                backTextColorHex: "#2B241E",
                stampAssetID: stampAssetID,
                locationLabel: nil,
                unlockDate: now.addingTimeInterval(86_400)
            )
        }

        await #expect(throws: PostcardCreationError.missingStamp) {
            _ = try await service.create(input(stampAssetID: nil))
        }
        await #expect(throws: PostcardCreationError.unknownStamp) {
            _ = try await service.create(input(stampAssetID: "retired-stamp"))
        }

        service.discard([photo])
    }
}

@MainActor
private final class FailingCreateStore: PostcardStore {
    struct Boom: Error {}

    func create(_ postcard: Postcard) async throws { throw Boom() }
    func postcard(withID id: UUID) async throws -> Postcard? { nil }
    func timeline(offset: Int, limit: Int) async throws -> [Postcard] { [] }
    func sealedPostcards() async throws -> [Postcard] { [] }
    func update(_ postcard: Postcard) async throws {}
    func delete(_ postcard: Postcard) async throws {}
}
