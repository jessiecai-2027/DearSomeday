//
//  Manifest.swift
//  DearFutureMe
//
//  Codable model for the §6.2 portable bundle manifest (`manifest.json`).
//
//  Standalone: no SwiftData, no dependency on the rest of the app. This file
//  defines the wire format only — no file I/O, no directory walking, no photo
//  copying. Whoever writes the exporter/importer (build-order step past §6.2)
//  reads and writes these types.
//
//  ── Why the manifest state has no `draft` case ────────────────────────────
//  §6.1's *domain* model is `draft | sealed | unlocked`. §6.2's *manifest*
//  is explicitly `sealed | unlocked`. A draft is a work-in-progress that lives
//  only in the composer's memory — it never persists (the store rejects drafts;
//  see `PostcardStore.create`) and so is never exported. Rather than model
//  `draft` here and reject it at runtime, `ManifestState` simply omits it — an
//  unexportable draft is unrepresentable, so the "don't export a draft" rule is
//  enforced by the type system, not a guard clause. This split is correct and
//  kept; no third state was added.
//
//  ── Date strategy: ISO-8601, whole-second ─────────────────────────────────
//  §6.2 spells the timestamps "ISO-8601", so we use `JSONEn/Decoder`'s
//  `.iso8601` strategy (Foundation's `ISO8601DateFormatter`, RFC 3339). It's
//  the portable choice: an Android reader can parse it with any ISO-8601
//  library, which `.deferredToDate` (seconds-since-2001 as a Double) could not.
//
//  `.iso8601` uses `.withInternetDateTime` only — it does NOT emit or parse
//  fractional seconds. So it DROPS sub-second precision. `Date()` carries
//  sub-second precision, which means a freshly-captured timestamp would not
//  survive an encode→decode round-trip unchanged. To keep round-trip equality,
//  every `Date` is truncated to a whole second *on the way in* (the memberwise
//  init below), so what we hold already matches what the wire can represent.
//
//  Limitation this accepts: a manifest written elsewhere WITH fractional
//  seconds (e.g. "…:00.5Z") will fail `.iso8601` decoding. That's fine for v1 —
//  we control both writers — and belongs in the importer's "corrupt bundle"
//  path (§7.2), not here. Use `Manifest.makeEncoder()` / `makeDecoder()` so
//  the strategy stays in one place.

import Foundation

// MARK: - Root

struct Manifest: Codable, Equatable {

    /// Current on-disk schema. Bump when the manifest shape changes.
    static let latestSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var title: String
    var description: String
    var createdAt: Date
    var editableUntil: Date
    var unlockDate: Date
    var state: ManifestState
    var photos: [PhotoRef]
    var decoration: Decoration

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case title
        case description
        case createdAt
        case editableUntil
        case unlockDate
        case state
        case photos
        case decoration
    }

    /// Truncates every timestamp to a whole second on construction so that
    /// encode→decode under the `.iso8601` strategy is exactly reversible.
    init(
        schemaVersion: Int = Manifest.latestSchemaVersion,
        id: UUID,
        title: String,
        description: String,
        createdAt: Date,
        editableUntil: Date,
        unlockDate: Date,
        state: ManifestState,
        photos: [PhotoRef],
        decoration: Decoration
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt.truncatedToWholeSecond
        self.editableUntil = editableUntil.truncatedToWholeSecond
        self.unlockDate = unlockDate.truncatedToWholeSecond
        self.state = state
        self.photos = photos
        self.decoration = decoration
    }
}

// MARK: - State

/// §6.2 manifest state. Deliberately excludes §6.1's `draft` — see file header.
enum ManifestState: String, Codable, Equatable {
    case sealed
    case unlocked
}

// MARK: - Photos

struct PhotoRef: Codable, Equatable {
    /// Bundle-relative path, e.g. "photos/01.jpg".
    var file: String
    /// Display order, 0-based.
    var order: Int

    enum CodingKeys: String, CodingKey {
        case file
        case order
    }
}

// MARK: - Decoration

struct Decoration: Codable, Equatable {
    var substrateId: String
    var elements: [DecorationElement]

    enum CodingKeys: String, CodingKey {
        case substrateId
        case elements
    }
}

struct DecorationElement: Codable, Equatable {
    var id: UUID
    var type: ElementType
    var assetId: String
    /// Normalised 0–1 relative to card bounds (§6.2).
    var position: Position
    /// Degrees.
    var rotation: Double
    var scale: Double
    /// Paint order; higher is nearer the top (§6.2).
    var zIndex: Int
    /// Present only for `.text` elements.
    var text: String?
    /// Present only for `.text` elements.
    var fontId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case assetId
        case position
        case rotation
        case scale
        case zIndex
        case text
        case fontId
    }
}

enum ElementType: String, Codable, Equatable {
    case sticker
    case tape
    case stamp
    case text
    case photoFrame
}

struct Position: Codable, Equatable {
    /// Normalised 0–1.
    var x: Double
    /// Normalised 0–1.
    var y: Double

    enum CodingKeys: String, CodingKey {
        case x
        case y
    }
}

// MARK: - JSON configuration

extension Manifest {

    /// The one place the `.iso8601` date strategy is applied. Both the exporter
    /// and any test must use these so round-trip equality holds.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Date truncation

private extension Date {
    /// Drops sub-second precision to match what the `.iso8601` wire format can
    /// represent. Floors toward the past so it agrees with the formatter, which
    /// discards the fractional part rather than rounding it.
    var truncatedToWholeSecond: Date {
        Date(timeIntervalSinceReferenceDate:
                timeIntervalSinceReferenceDate.rounded(.down))
    }
}
