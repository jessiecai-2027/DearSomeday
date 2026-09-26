//
//  PostcardDisplayView.swift
//  DearFutureMe
//
//  The read view (§5.6), reached only from an unlocked timeline row. Ugly on
//  purpose (system text + images, no scrapbook canvas — that's step 4).
//
//  ── §5.4 re-verify on open ─────────────────────────────────────────────────
//  Even though we arrived from an unlocked row, this re-checks trusted time
//  before revealing: it runs `unlockIfDue` on open and only shows contents if
//  the card is genuinely `.unlocked`. Today the row is always already unlocked,
//  but this is the defense the notification-tap path (task G) will lean on — a
//  local notification fires on *device* time (spoofable, §5.4), so tapping it
//  must not be a way to peek. If the card isn't really unlocked, we show a quiet
//  waiting state instead.
//
//  ── §5.6 top bar ───────────────────────────────────────────────────────────
//  The known bug was a top bar that half-animates while scrolling. Per the
//  decision to "remove it entirely", the navigation bar is hidden here; a single
//  floating Done control replaces it.
//

import SwiftUI
import UIKit

struct PostcardDisplayView: View {

    let card: Postcard
    let services: AppServices

    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var photosByID: [UUID: UIImage] = [:]
    @State private var photosByOrder: [Int: UIImage] = [:]

    var body: some View {
        Group {
            if revealed {
                content
            } else {
                waiting
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)       // §5.6: no top bar
        .appBackground()
        .overlay(alignment: .topLeading) {
            Button("Done") { dismiss() }
                .font(Tokens.Font.button)
                .padding()
        }
        .task { await monitorGate() }
    }

    // MARK: - Gate

    /// Keeps a notification-opened waiting screen live. A device-time
    /// notification may arrive just before trusted time reaches the same
    /// instant, so retry locally without treating the notification as proof.
    private func monitorGate() async {
        while !Task.isCancelled {
            if await openGate() { return }
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    /// - Returns: `true` once contents may be revealed; otherwise `false` so
    ///   the cancellable monitor can retry when trusted time advances.
    private func openGate() async -> Bool {
        // Re-verify against trusted time; persist if this open is what unlocked it.
        if services.lifecycle.unlockIfDue(card) {
            try? await services.store.update(card)
        }
        guard card.state == .unlocked else {
            return false
        }
        await loadPhotos()
        revealed = true
        return true
    }

    private func loadPhotos() async {
        let ordered = card.photos.sorted { $0.order < $1.order }
        var images: [UUID: UIImage] = [:]
        var orderedImages: [Int: UIImage] = [:]
        for photo in ordered {
            if let data = services.photoStore.loadData(fileName: photo.fileName),
               let image = UIImage(data: data) {
                images[photo.id] = image
                orderedImages[photo.order] = image
            }
        }
        photosByID = images
        photosByOrder = orderedImages
    }

    // MARK: - States

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(card.title.isEmpty ? "(untitled)" : card.title)
                    .font(Tokens.Font.screenTitle)
                    .lineSpacing(-6)

                PostcardSurfaceView(card: card, photosByID: photosByID, photosByOrder: photosByOrder)
            }
            .padding()
            .padding(.top, 44)          // clear the floating Done control
        }
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    private var waiting: some View {
        VStack(spacing: 12) {
            Image("EnvelopeClosed")
                .resizable()
                .scaledToFit()
                .envelopePaperTone()
                .frame(width: Tokens.Timeline.envelopeWidth,
                       height: Tokens.Timeline.envelopeHeight)
                .accessibilityHidden(true)
            Text("Still locked")
            if let date = card.unlockDate {
                Text("Opens \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.chromeText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
