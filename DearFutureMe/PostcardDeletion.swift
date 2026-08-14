//
//  PostcardDeletion.swift
//  DearFutureMe
//
//  The "delete on card delete" composition flagged in task A: the store removes
//  only the record, so deleting a card's photo bytes is a separate call. This is
//  the one place that pairs them, so no caller forgets the bytes and leaks them.
//
//  Order matters: capture the file names FIRST (a deleted SwiftData object may
//  fault when its properties are read afterward), delete the record, THEN drop
//  the bytes. If the record delete throws, the bytes are untouched — no
//  half-deleted card. If the byte cleanup silently fails, the worst case is an
//  orphaned file, never a card pointing at missing photos.
//

import Foundation

enum PostcardDeletion {

    /// Permanently deletes `card` and its photo bytes (§5.3 — no recovery bin).
    /// The caller owns the confirmation UX; this just performs the deletion.
    static func delete(
        _ card: Postcard,
        from store: PostcardStore,
        photoStore: PhotoStore
    ) async throws {
        let fileNames = card.photos.map(\.fileName)
        try await store.delete(card)
        photoStore.delete(fileNames: fileNames)
    }
}
