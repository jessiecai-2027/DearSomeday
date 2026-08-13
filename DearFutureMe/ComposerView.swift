//
//  ComposerView.swift
//  DearFutureMe
//
//  The create side of the loop (§5.1), intentionally ugly (system Form, no
//  Tokens — styling is step 4). Scope for the ugly loop: multi-photo pick
//  (deduped, ≤10, auto center-cropped to 4:5 on import), title, description,
//  unlock day, seal. Crop UI and carousel reorder are deferred by decision.
//
//  ── The four §5.1 known bugs, designed out from the start ──────────────────
//   • Duplicate photos — picked assets are deduped by `itemIdentifier`.
//   • Description grows infinitely — the TextEditor has a FIXED height and
//     scrolls internally.
//   • Keyboard trap — a keyboard-toolbar "Done" dismisses it, and the form
//     dismisses it interactively on scroll.
//   • Title-bar mismatch — N/A here (no custom chrome yet); revisit at step 4.
//
//  ── Photo-byte lifecycle ───────────────────────────────────────────────────
//  Photos are cropped + written to the PhotoStore ON IMPORT, so we can show a
//  thumbnail and hand the card real file handles at seal. If the composer is
//  dismissed WITHOUT sealing (Cancel, swipe, or removing a photo), those bytes
//  are orphaned — so they're deleted: per-photo on remove, and the whole
//  pending set in `onDisappear` when the seal wasn't committed. Deletion is
//  idempotent, so overlapping cleanup paths are harmless.
//

import SwiftUI
import PhotosUI
import UIKit

struct ComposerView: View {

    let services: AppServices

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var message = ""
    @State private var chosenDate = ComposerView.defaultDay()

    @State private var pendingPhotos: [PendingPhoto] = []
    @State private var addedIdentifiers: Set<String> = []
    @State private var pickerItems: [PhotosPickerItem] = []

    @State private var isSealing = false
    @State private var committed = false
    @State private var errorMessage: String?

    @FocusState private var focus: Field?
    private enum Field { case title, message }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                titleSection
                messageSection
                dateSection
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Postcard")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Seal") { Task { await seal() } }
                        .disabled(isSealing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
        }
        .interactiveDismissDisabled(isSealing)
        .onChange(of: pickerItems) { _, items in
            Task { await importPicked(items) }
        }
        .onDisappear {
            // Dismissed without sealing → drop the orphaned bytes.
            if !committed {
                services.photoStore.delete(fileNames: pendingPhotos.map(\.fileName))
            }
        }
    }

    // MARK: - Sections

    private var photosSection: some View {
        Section {
            if !pendingPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingPhotos) { thumbnail($0) }
                    }
                    .padding(.vertical, 4)
                }
            }
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: ComposerLogic.maxPhotos,
                matching: .images
            ) {
                Text(pendingPhotos.isEmpty ? "Add photos" : "Add more photos")
            }
            .disabled(pendingPhotos.count >= ComposerLogic.maxPhotos)
        } header: {
            HStack {
                Text("Photos")
                Spacer()
                Text("\(pendingPhotos.count) / \(ComposerLogic.maxPhotos)")   // count indicator, top-right (§5.1)
            }
        }
    }

    private func thumbnail(_ photo: PendingPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = photo.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.gray)
                }
            }
            .frame(width: 72, height: 90)       // 4:5
            .clipped()

            Button {
                remove(photo)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black)
            }
            .padding(2)
            .accessibilityLabel("Remove photo")
        }
    }

    private var titleSection: some View {
        Section {
            TextField("Title", text: $title)
                .focused($focus, equals: .title)
                .onChange(of: title) { _, new in
                    if new.count > ComposerLogic.maxTitleLength {
                        title = String(new.prefix(ComposerLogic.maxTitleLength))
                    }
                }
        } header: {
            HStack {
                Text("Title")
                Spacer()
                Text("\(title.count) / \(ComposerLogic.maxTitleLength)")
            }
        }
    }

    private var messageSection: some View {
        Section {
            TextEditor(text: $message)
                .focused($focus, equals: .message)
                .frame(height: 140)             // fixed height — must not grow (§5.1)
                .onChange(of: message) { _, new in
                    if new.count > ComposerLogic.maxMessageLength {
                        message = String(new.prefix(ComposerLogic.maxMessageLength))
                    }
                }
        } header: {
            HStack {
                Text("Message")
                Spacer()
                Text("\(message.count) / \(ComposerLogic.maxMessageLength)")
            }
        }
    }

    private var dateSection: some View {
        Section {
            DatePicker("Unlock date", selection: $chosenDate, in: Date()..., displayedComponents: .date)
        } footer: {
            Text("Opens at 9:00am on the day you choose.")
        }
    }

    // MARK: - Photo import

    private func importPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard pendingPhotos.count < ComposerLogic.maxPhotos else { break }
            let identifier = item.itemIdentifier
            if let identifier, addedIdentifiers.contains(identifier) { continue }   // dedup (§5.1)
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { continue }
            do {
                let fileName = try services.photoStore.save(image)   // 4:5 crop + ≤2048 + q0.8
                let thumb = services.photoStore.loadData(fileName: fileName).flatMap(UIImage.init(data:))
                pendingPhotos.append(PendingPhoto(fileName: fileName, identifier: identifier, image: thumb))
                if let identifier { addedIdentifiers.insert(identifier) }
            } catch {
                // Couldn't process/store this one — skip it, keep the rest.
            }
        }
        pickerItems = []   // reset so re-picking the same asset fires onChange again
    }

    private func remove(_ photo: PendingPhoto) {
        services.photoStore.delete(fileNames: [photo.fileName])   // discard bytes now
        pendingPhotos.removeAll { $0.id == photo.id }
        if let identifier = photo.identifier { addedIdentifiers.remove(identifier) }
    }

    // MARK: - Seal

    private func seal() async {
        guard !isSealing else { return }
        isSealing = true
        defer { isSealing = false }
        errorMessage = nil
        focus = nil

        // Ensure trusted time (§5.4). The launch sweep usually synced already,
        // but the composer may be the first network-touching action if launch
        // was offline.
        if case .neverSynced = services.clock.now() {
            await services.clock.syncFromServer()
        }
        guard case .trusted(let now) = services.clock.now() else {
            errorMessage = ComposerLogic.sealErrorCopy(.trustedTimeUnavailable)
            return
        }

        let unlockDate = ComposerLogic.unlockInstant(onDayOf: chosenDate, calendar: .current)
        let storedPhotos = pendingPhotos.enumerated().map { index, photo in
            StoredPhoto(order: index, fileName: photo.fileName)
        }
        let draft = Postcard(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message,
            photos: storedPhotos,
            createdAt: now,             // trusted, so the edit window (§5.3.3) is honest
            state: .draft
        )

        do {
            try services.lifecycle.seal(draft, unlockDate: unlockDate)
            try await services.store.create(draft)
            committed = true            // keep the photo bytes; skip onDisappear cleanup
            dismiss()
        } catch let error as PostcardLifecycle.SealError {
            errorMessage = ComposerLogic.sealErrorCopy(error)
        } catch {
            errorMessage = "Couldn’t save this postcard. Please try again."
        }
    }

    // MARK: - Helpers

    /// Default the picker to tomorrow — the nearest day whose 9am is reliably in
    /// the future regardless of the current time of day.
    private static func defaultDay() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private struct PendingPhoto: Identifiable {
        let id = UUID()
        let fileName: String
        /// The source asset's `itemIdentifier`, used to dedup repeat picks.
        let identifier: String?
        let image: UIImage?
    }
}
