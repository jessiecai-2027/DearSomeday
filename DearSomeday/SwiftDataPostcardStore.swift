//
//  SwiftDataPostcardStore.swift
//  DearSomeday
//
//  The v1 production `PostcardStore` (§3): a SwiftData conformer over the §6.1
//  models. Phase 2 swaps this for a CloudKit-backed conformer without touching
//  the protocol or its callers — the whole point of the seam.
//
//  ── Read strategy: fetch, then process in memory ───────────────────────────
//  `timeline` and `sealedPostcards` fetch the non-draft / sealed cards and
//  filter-and-sort in Swift, not in a FetchDescriptor. The §5.5 order is two
//  groups with opposite sort directions, which a single descriptor can't
//  express (see PostcardTimelineSort); `sealedPostcards` filters on the enum
//  `state`, which `#Predicate` handles awkwardly. At v1 scale this is the
//  accepted trade — both are launch/scroll operations over a small store, not a
//  hot path. Single-object lookups by `id` DO use a predicate, which SwiftData
//  handles cleanly.
//
//  ── The two invariants the schema can't enforce, enforced here ─────────────
//  §3 forbids unique constraints, so `Postcard.id` uniqueness and the
//  "drafts never persist" rule are application invariants. `create` upholds
//  both: it refuses a draft and refuses a colliding id. Both are caller misuse
//  (a draft belongs in the composer's memory; a duplicate id is a minting bug),
//  so — matching the protocol contract and the in-memory double — they
//  `assertionFailure` in debug and no-op in release rather than throw. The
//  `throws` channel is reserved for real write failures (storage full, §7.2).
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataPostcardStore: PostcardStore {

    private let container: ModelContainer

    /// The main-actor context. The §6.1 models are MainActor-isolated, so all
    /// store work happens here; a Phase 2 CloudKit conformer can move network
    /// work off-actor behind the same async API without changing callers.
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Builds the app's `ModelContainer`. `inMemory` gives tests an ephemeral
    /// store with no disk footprint and no cross-test bleed.
    ///
    /// v1 is local-only — no `cloudKitDatabase` is configured (a free Apple ID
    /// can't create a container anyway, §3). Phase 2 turns that on here, which
    /// is why the CloudKit-legality rules in Models.swift matter from commit one.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Postcard.self, DesignPreset.self])
        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let storeURL = try localStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            try quarantineStore(at: storeURL)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    // MARK: - Create

    func create(_ postcard: Postcard) async throws {
        // Drafts live only in the composer's memory — a persisted draft would be
        // unreachable (timeline hides it, no drafts fetch). Caller misuse.
        guard postcard.state != .draft else {
            assertionFailure("create() was passed a draft; drafts live in the composer, not the store")
            return
        }
        // Uniqueness invariant (§3 forbids a store-level unique constraint):
        // never silently store a second copy under a colliding id.
        guard try existing(id: postcard.id) == nil else {
            assertionFailure("create() was passed a duplicate id \(postcard.id)")
            return
        }
        context.insert(postcard)
        try context.save()
    }

    // MARK: - Fetch (single)

    func postcard(withID id: UUID) async throws -> Postcard? {
        try existing(id: id)
    }

    // MARK: - Fetch (timeline, ordered + paginated — §5.5)

    func timeline(offset: Int, limit: Int) async throws -> [Postcard] {
        // Drafts are excluded (§5.5). Filter defensively too — create() keeps
        // them out, but an update-to-draft must not leak one onto the timeline.
        let visible = try context.fetch(FetchDescriptor<Postcard>())
            .filter { $0.state != .draft }
        let ordered = visible.sorted(by: PostcardTimelineSort.precedes)

        // Crash-safe slice for any offset/limit, including out-of-range values.
        let start = min(max(0, offset), ordered.count)
        let end = min(start + max(0, limit), ordered.count)
        return Array(ordered[start..<end])
    }

    // MARK: - Fetch (all sealed — §5.7)

    func sealedPostcards() async throws -> [Postcard] {
        try context.fetch(FetchDescriptor<Postcard>())
            .filter { $0.state == .sealed }
    }

    // MARK: - Update

    func update(_ postcard: Postcard) async throws {
        guard let managed = try existing(id: postcard.id) else {
            // Update targets an existing card; updating an absent one is misuse.
            assertionFailure("update() was passed a postcard that isn't stored: \(postcard.id)")
            return
        }
        // The common path is a live managed object mutated in place, where
        // `managed === postcard` and this is just a save. When a *distinct*
        // instance carrying the same id is passed, copy its fields onto the
        // managed object rather than inserting a second copy (which would break
        // the id-uniqueness invariant). Identity of the passed instance is not
        // preserved in that case — only its values, which is all the protocol
        // promises. (The in-memory double swaps by reference; SwiftData can't,
        // since a foreign instance isn't a managed object.)
        if managed !== postcard {
            copyState(from: postcard, to: managed)
        }
        try context.save()
    }

    // MARK: - Delete

    func delete(_ postcard: Postcard) async throws {
        // "Deleting a card that is not present is a no-op, not an error." Delete
        // the *managed* object found by id, not the passed instance (which may
        // be foreign). Photo-byte cleanup is the caller's concern (PhotoStore) —
        // the store only removes the record.
        guard let managed = try existing(id: postcard.id) else { return }
        context.delete(managed)
        try context.save()
    }

    // MARK: - Helpers

    /// The managed card with this domain `id`, or nil. `#Predicate` on a `UUID`
    /// is well-supported; `fetchLimit = 1` since the uniqueness invariant means
    /// at most one match.
    private func existing(id: UUID) throws -> Postcard? {
        var descriptor = FetchDescriptor<Postcard>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Copies every mutable field except `id` from a foreign instance onto the
    /// managed one (the `update` foreign-instance path).
    private func copyState(from source: Postcard, to destination: Postcard) {
        destination.schemaVersion = source.schemaVersion
        destination.title = source.title
        destination.message = source.message
        destination.photos = source.photos
        destination.templateId = source.templateId
        destination.slotAssignments = source.slotAssignments
        destination.backText = source.backText
        destination.backFontId = source.backFontId
        destination.backFontPointSize = source.backFontPointSize
        destination.backTextColorHex = source.backTextColorHex
        destination.locationLabel = source.locationLabel
        destination.animationMetadata = source.animationMetadata
        destination.createdAt = source.createdAt
        destination.unlockDate = source.unlockDate
        destination.editableUntil = source.editableUntil
        destination.state = source.state
        destination.substrateId = source.substrateId
        destination.decorationElements = source.decorationElements
    }

    private static func localStoreURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Stores", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("DearSomeday.store")
    }

    /// Development-stage schema changes can make SwiftData refuse to open the
    /// local store before the app reaches any screen. Move the incompatible
    /// SQLite files aside and retry with an empty local store. This preserves
    /// the old files for manual recovery while keeping the MVP usable.
    private static func quarantineStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]
        guard candidates.contains(where: { fileManager.fileExists(atPath: $0.path) }) else { return }

        let quarantineDirectory = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("IncompatibleStores", isDirectory: true)
            .appendingPathComponent(String(Int(Date().timeIntervalSince1970)), isDirectory: true)
        try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)

        for file in candidates where fileManager.fileExists(atPath: file.path) {
            let destination = quarantineDirectory.appendingPathComponent(file.lastPathComponent)
            try? fileManager.moveItem(at: file, to: destination)
        }
    }
}
