//
//  Models.swift
//  DearFutureMe
//
//  SwiftData models for the §6.1 domain: `Postcard` and `DesignPreset`.
//
//  Scope of this file: MODELS ONLY. No `PostcardStore` protocol, no store
//  implementation, no file/photo-byte I/O, no export/import. Just the persisted
//  shape and the value types it embeds.
//
//  ── The §3 CloudKit rules are load-bearing, not stylistic ──────────────────
//  v1 ships local-only, but v1.1 turns on CloudKit sync as an *implementation
//  swap* behind a store protocol — NOT a schema migration. That only holds if
//  the schema is CloudKit-legal from the first commit. NSPersistentCloudKit-
//  Container imposes three hard rules; SwiftData inherits them:
//
//    1. Every property optional or defaulted.
//    2. No unique constraints (`@Attribute(.unique)` is illegal).
//    3. No required (non-optional) relationships.
//
//  Every property below is defaulted or optional. There is no `.unique`. There
//  are no relationships at all (see the embedding decision below).
//
//  ── Where the rules forced an awkward shape (as asked) ─────────────────────
//
//  A. `id` is a plain, NON-unique UUID.
//     §6.1 wants `id` to be the card's identity ("own UUID, never a platform
//     record ID"). Rule 2 forbids enforcing that at the store level, so the
//     database will happily hold two cards with the same `id`. Uniqueness is
//     now an APPLICATION invariant — whoever mints cards must guarantee it, and
//     any import path must dedupe. The type system can't help. This is the most
//     load-bearing awkwardness and the easiest to forget.
//
//  B. Lifecycle invariants can no longer live in the types.
//     Rule 1 means "a sealed card always has an unlockDate" is inexpressible:
//     `unlockDate`/`editableUntil` MUST be optional (a `draft` genuinely has no
//     unlock date yet, so here optionality is also honest — but even if it
//     weren't, the rule would force it). The lock lifecycle layer (§5.3) owns
//     the "sealed ⇒ unlockDate != nil" invariant now, not the schema. Read a
//     sealed card's `unlockDate!` nowhere; unwrap defensively.
//
//  C. Photos and decoration are EMBEDDED value types, not related entities.
//     The obvious modelling of `photos: [PhotoRef]` and `decorationElements`
//     is child @Model classes with relationships. Rule 3 would force those
//     relationships optional AND (for CloudKit) require explicit inverses,
//     buying the classic nil-vs-empty ambiguity and ordering headaches for
//     collections that are (a) owned by exactly one card, (b) never queried
//     independently, (c) capped tiny (≤10 photos §5.1, ≤20 elements §4.4).
//     That is composition, not association — so they're stored as Codable
//     value arrays (one encoded attribute each). Order is preserved for free,
//     no inverses, no relationship rules to satisfy. If a future need arises to
//     query elements across cards, THAT is when to promote them to entities.
//
//  ── Deliberately NOT reusing the Manifest (§6.2) types ─────────────────────
//  Manifest.swift is the FROZEN portable wire contract ("keeps any future
//  Android app compatible"); its header states it has no SwiftData dependency.
//  These storage types are a different layer: they carry `draft` (the wire
//  omits it), they hold local photo identifiers rather than bundle-relative
//  paths, and they will evolve with CloudKit/SwiftData needs. Coupling the two
//  would mean a storage tweak could break the wire format or vice versa. The
//  model⇄manifest mapping is a one-shot at the export/import boundary (a later
//  step), which is the right place to pay for the small duplication below.
//

import Foundation
import SwiftData

// MARK: - Postcard

@Model
final class Postcard {

    /// Current on-disk schema for the local store. Independent of the bundle's
    /// `Manifest.latestSchemaVersion` — the two layers version separately.
    static let latestSchemaVersion = 1

    /// The card's domain identity (§6.1). This is NOT `.unique` — rule 2 —
    /// so uniqueness is an application invariant, not a store guarantee. Also
    /// distinct from SwiftData's own `persistentModelID`, which is a store
    /// record handle, never exported.
    var id: UUID = UUID()

    var schemaVersion: Int = Postcard.latestSchemaVersion

    /// §5.1: empty title permitted (max 60 chars — enforced in the composer).
    var title: String = ""

    /// §6.1's `description`, renamed to avoid shadowing `CustomStringConvertible.
    /// description` on a class (a well-known SwiftData footgun). §5.1: empty
    /// permitted (max 2,000 chars — enforced in the composer). Maps to the
    /// manifest's `description` field at the export boundary.
    var message: String = ""

    /// Ordered (§6.1). Order is carried by `StoredPhoto.order` and by array
    /// index; keep them consistent. Empty = text-only card (§5.1 permits it).
    var photos: [StoredPhoto] = []

    /// Always known at creation. Optional-or-defaulted rule satisfied by the
    /// default; a card without a creation instant is meaningless, so we default
    /// rather than make it optional.
    var createdAt: Date = Date()

    /// nil until sealed (§5.3). Stored as an absolute UTC instant (§5.3) — a
    /// `Date` is timezone-agnostic, so this is automatic. Never wall-clock.
    var unlockDate: Date? = nil

    /// End of the 1-week edit window (§5.3); truncates if `unlockDate` arrives
    /// first. nil until the window is established. Owned by the lifecycle layer.
    var editableUntil: Date? = nil

    /// draft | sealed | unlocked (§6.1). New cards start as drafts.
    /// Fully qualified (not `.draft`): the `@Model` macro rewrites default
    /// values without enum type context, so leading-dot shorthand fails to
    /// compile here.
    var state: PostcardState = PostcardState.draft

    /// The chosen substrate asset (§4.2). nil on a fresh draft before a
    /// substrate is picked.
    var substrateId: String? = nil

    /// Canvas decoration (§5.2 / §6.2). `zIndex` on each element determines
    /// paint order; positions are normalised 0–1.
    var decorationElements: [CanvasElement] = []

    init(
        id: UUID = UUID(),
        schemaVersion: Int = Postcard.latestSchemaVersion,
        title: String = "",
        message: String = "",
        photos: [StoredPhoto] = [],
        createdAt: Date = Date(),
        unlockDate: Date? = nil,
        editableUntil: Date? = nil,
        state: PostcardState = .draft,
        substrateId: String? = nil,
        decorationElements: [CanvasElement] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.title = title
        self.message = message
        self.photos = photos
        self.createdAt = createdAt
        self.unlockDate = unlockDate
        self.editableUntil = editableUntil
        self.state = state
        self.substrateId = substrateId
        self.decorationElements = decorationElements
    }
}

// MARK: - DesignPreset

/// A saved, reusable decoration recipe (§5.1: "Save decorated cards as reusable
/// design presets"). Has no lifecycle and no photos — it's styling only.
@Model
final class DesignPreset {

    /// Domain identity. NOT `.unique` — same rule-2 caveat as `Postcard.id`.
    var id: UUID = UUID()

    var name: String = ""

    var substrateId: String? = nil

    /// Default font for text elements applied by this preset. nil = system
    /// fallback (§4.6 fonts are still open).
    var fontId: String? = nil

    /// The preset's colour choices — token names or hex strings, kept as plain
    /// strings so the palette (§4.3) can evolve without a schema change.
    var colorSet: [String] = []

    var decorationElements: [CanvasElement] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        substrateId: String? = nil,
        fontId: String? = nil,
        colorSet: [String] = [],
        decorationElements: [CanvasElement] = []
    ) {
        self.id = id
        self.name = name
        self.substrateId = substrateId
        self.fontId = fontId
        self.colorSet = colorSet
        self.decorationElements = decorationElements
    }
}

// MARK: - Embedded value types
//
// Stored inline on the models above as Codable attributes (see decision C).
// Every field is defaulted so a malformed/partial decode still yields a usable
// value rather than throwing — these live inside one big encoded blob, so a
// single bad field shouldn't nuke the whole card.

/// §6.1 domain lifecycle. The manifest (§6.2) deliberately omits `draft`; that
/// exclusion is the wire layer's concern, not this one.
enum PostcardState: String, Codable, CaseIterable {
    case draft
    case sealed
    case unlocked
}

/// One photo slot on a card. The display-resolution JPEG bytes (§6.1: longest
/// edge 2048px, q0.8) are NOT stored here — byte storage is a later layer.
/// `fileName` is the local handle to those bytes; `order` is the 0-based
/// display position (§6.1: photos are ordered).
struct StoredPhoto: Codable, Equatable, Hashable {
    var order: Int = 0
    var fileName: String = ""

    init(order: Int = 0, fileName: String = "") {
        self.order = order
        self.fileName = fileName
    }
}

/// A single decoration element on the canvas. Mirrors §6.2's decoration element
/// but flattened (no nested `Position`) and storage-owned — see the "not
/// reusing Manifest types" note in the file header.
struct CanvasElement: Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var kind: CanvasElementKind = .sticker
    var assetId: String = ""
    /// Normalised 0–1, relative to card bounds (§6.2).
    var x: Double = 0.5
    var y: Double = 0.5
    /// Degrees.
    var rotation: Double = 0
    var scale: Double = 1
    /// Paint order; higher is nearer the top (§6.2).
    var zIndex: Int = 0
    /// Present only for `.text` elements.
    var text: String? = nil
    /// Present only for `.text` elements.
    var fontId: String? = nil

    init(
        id: UUID = UUID(),
        kind: CanvasElementKind = .sticker,
        assetId: String = "",
        x: Double = 0.5,
        y: Double = 0.5,
        rotation: Double = 0,
        scale: Double = 1,
        zIndex: Int = 0,
        text: String? = nil,
        fontId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.assetId = assetId
        self.x = x
        self.y = y
        self.rotation = rotation
        self.scale = scale
        self.zIndex = zIndex
        self.text = text
        self.fontId = fontId
    }
}

/// §6.2 element types. Named `kind` on `CanvasElement` to avoid colliding with
/// Swift's `type`; the raw values match the wire vocabulary so the boundary
/// mapping is 1:1.
enum CanvasElementKind: String, Codable, CaseIterable {
    case sticker
    case tape
    case stamp
    case text
    case photoFrame
}
