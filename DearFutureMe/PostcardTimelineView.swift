//
//  PostcardTimelineView.swift
//  DearFutureMe
//
//  The app's root, replacing the token-test ContentView. **Intentionally ugly**
//  (BUILD-PLAN step 3): system List, no textures, no Tokens. The scrapbook look
//  is step 4. Responsibilities:
//   • run the unlock sweep on launch and every foreground (§5.4), and re-scan +
//     re-schedule notifications each time (§5.7);
//   • show the timeline in §5.5 order, paged in batches of 50;
//   • sealed rows show the title + "Locked until…" only, loading NO photo bytes
//     (§5.3.2); unlocked rows show a thumbnail and open the display view (§5.6);
//   • delete on every card with confirmation, hold-to-confirm for locked (§5.3);
//   • prime notification permission after the first seal (§7.1), surface a quiet
//     badge if denied (§7.2), and route notification taps through the display
//     view's re-verify (§5.4).
//
//  Not yet (deferred, not forgotten): compact/card view modes and the blurred
//  locked treatment (§5.5) are step-4 visuals; here "not loaded" stands in for
//  "blurred".
//

import SwiftUI
import UIKit

struct PostcardTimelineView: View {

    let services: AppServices

    /// §5.5 batch size.
    private static let pageSize = 50
    /// §7.1: prime once, after the first seal.
    private static let primedKey = "hasPrimedNotifications"

    @Environment(\.scenePhase) private var scenePhase

    @State private var cards: [Postcard] = []
    @State private var canLoadMore = false
    @State private var isBusy = false
    @State private var isLoadingPage = false

    @State private var showComposer = false
    @State private var sealedDuringComposer = false
    @State private var showPriming = false
    @State private var notificationsDenied = false
    @State private var deepLink: DeepLinkTarget?

    // Delete targets: unlocked uses a tap dialog; locked uses a hold-to-confirm
    // sheet (§5.3), so they are driven separately.
    @State private var unlockedDeleteTarget: Postcard?
    @State private var lockedDeleteTarget: DeleteTarget?

    var body: some View {
        NavigationStack {
            List {
                ForEach(cards, id: \.id) { card in
                    rowView(for: card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                requestDelete(card)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onAppear { maybeLoadMore(after: card) }
                }
            }
            .overlay {
                if cards.isEmpty && !isBusy {
                    emptyState
                }
            }
            .safeAreaInset(edge: .top) {
                if notificationsDenied {
                    deniedBanner
                }
            }
            .navigationTitle("Postcards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showComposer = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New postcard")
                }
            }
            #if DEBUG
            // TODO: remove before release (debug-only, like the §5.7 test button)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sweep") { Task { await sweepAndReload() } }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Seed 20s") { Task { await seedDebugCard() } }
                }
            }
            #endif
            .confirmationDialog(
                "Delete this postcard?",
                isPresented: Binding(
                    get: { unlockedDeleteTarget != nil },
                    set: { if !$0 { unlockedDeleteTarget = nil } }
                ),
                presenting: unlockedDeleteTarget
            ) { card in
                Button("Delete", role: .destructive) {
                    unlockedDeleteTarget = nil
                    Task { await performDelete(card) }
                }
                Button("Cancel", role: .cancel) { unlockedDeleteTarget = nil }
            } message: { _ in
                Text("This can’t be undone.")
            }
            .sheet(item: $lockedDeleteTarget) { target in
                LockedDeleteConfirmView(
                    card: target.card,
                    onConfirm: {
                        lockedDeleteTarget = nil
                        Task { await performDelete(target.card) }
                    },
                    onCancel: { lockedDeleteTarget = nil }
                )
            }
        }
        .sheet(isPresented: $showComposer, onDismiss: {
            Task {
                await reload()
                if sealedDuringComposer {
                    sealedDuringComposer = false
                    await rescheduleNotifications()
                    await maybePrimeNotifications()
                }
            }
        }) {
            ComposerView(services: services, onSealed: { sealedDuringComposer = true })
        }
        .sheet(isPresented: $showPriming) {
            NotificationPrimingView(
                onEnable: {
                    showPriming = false
                    UserDefaults.standard.set(true, forKey: Self.primedKey)
                    Task {
                        await services.notificationScheduler.requestAuthorization()
                        await rescheduleNotifications()
                    }
                },
                onSkip: {
                    showPriming = false
                    UserDefaults.standard.set(true, forKey: Self.primedKey)
                }
            )
        }
        // A notification tap opens the card through the display view, which
        // re-verifies trusted time before revealing anything (§5.4).
        .fullScreenCover(item: $deepLink) { target in
            PostcardDisplayView(card: target.card, services: services)
        }
        .onChange(of: services.notificationRouter.pendingCardID) { _, newID in
            guard let newID else { return }
            Task {
                if let card = try? await services.store.postcard(withID: newID) {
                    deepLink = DeepLinkTarget(id: newID, card: card)
                }
                services.notificationRouter.pendingCardID = nil
            }
        }
        // Fires on launch; the scenePhase handler covers every later foreground.
        .task { await sweepAndReload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await sweepAndReload() }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(for card: Postcard) -> some View {
        if card.state == .unlocked {
            NavigationLink {
                PostcardDisplayView(card: card, services: services)
            } label: {
                TimelineRowView(card: card, photoStore: services.photoStore)
            }
        } else {
            // Sealed cards are not tappable — contents are never revealed before
            // unlock (§5.3.2). Draft cards never reach the timeline.
            TimelineRowView(card: card, photoStore: services.photoStore)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No postcards yet.").font(.headline)
            Text("Write one to your future self.")
                .foregroundStyle(.secondary)
            Button("Create a postcard") { showComposer = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var deniedBanner: some View {
        HStack(spacing: 8) {
            Text("Notifications are off — you won’t be reminded when a postcard opens.")
                .font(.footnote)
            Spacer(minLength: 8)
            Button("Settings") { openSettings() }
                .font(.footnote)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.yellow.opacity(0.3))
    }

    // MARK: - Delete

    private func requestDelete(_ card: Postcard) {
        if card.state == .sealed {
            lockedDeleteTarget = DeleteTarget(id: card.id, card: card)
        } else {
            unlockedDeleteTarget = card
        }
    }

    private func performDelete(_ card: Postcard) async {
        try? await PostcardDeletion.delete(card, from: services.store, photoStore: services.photoStore)
        services.notificationScheduler.removePending(cardID: card.id)
        await reload()
    }

    // MARK: - Sweep + paging

    /// Runs the launch/foreground sweep, re-schedules notifications (§5.7), then
    /// refreshes from page one. The `isBusy` guard collapses the near-
    /// simultaneous launch `.task` and first `.active` transition into one pass
    /// and blocks overlapping sweeps.
    private func sweepAndReload() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        await services.coordinator.runSweep()
        await rescheduleNotifications()
        await reload()
    }

    /// Resets to the first page. Called after a sweep, a compose, or a delete —
    /// any change that can reorder or shrink the list.
    private func reload() async {
        let page = (try? await services.store.timeline(offset: 0, limit: Self.pageSize)) ?? []
        cards = page
        canLoadMore = (page.count == Self.pageSize)
    }

    private func maybeLoadMore(after card: Postcard) {
        guard card.id == cards.last?.id else { return }
        Task { await loadNextPage() }
    }

    private func loadNextPage() async {
        guard canLoadMore, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let page = (try? await services.store.timeline(offset: cards.count, limit: Self.pageSize)) ?? []
        cards.append(contentsOf: page)
        canLoadMore = (page.count == Self.pageSize)
    }

    // MARK: - Notifications (§5.7)

    /// Re-scan all sealed cards and re-schedule (§5.7), then refresh the denied
    /// badge. No-op scheduling if permission isn't granted.
    private func rescheduleNotifications() async {
        let sealed = (try? await services.store.sealedPostcards()) ?? []
        await services.notificationScheduler.reschedule(for: sealed)
        notificationsDenied = (await services.notificationScheduler.authorizationStatus() == .denied)
    }

    /// Prime exactly once, immediately after the first seal (§7.1).
    private func maybePrimeNotifications() async {
        guard !UserDefaults.standard.bool(forKey: Self.primedKey) else { return }
        showPriming = true
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Debug seeding

    #if DEBUG
    // TODO: remove before release
    /// Seals a real card 20 seconds out so the sweep can be watched on device:
    /// background/foreground (or tap Sweep) after 20s and it flips to ✅.
    private func seedDebugCard() async {
        await services.clock.syncFromServer()
        guard case .trusted(let now) = services.clock.now() else {
            print("[seed] no trusted time yet — connect to a network and retry")
            return
        }
        let draft = Postcard(
            title: "Debug \(Int(now.timeIntervalSince1970) % 1000)",
            createdAt: now,
            state: .draft
        )
        do {
            try services.lifecycle.seal(draft, unlockDate: now.addingTimeInterval(20))
            try await services.store.create(draft)
            await reload()
        } catch {
            print("[seed] failed: \(error)")
        }
    }
    #endif
}

// MARK: - Row

private struct TimelineRowView: View {

    let card: Postcard
    let photoStore: PhotoStore

    @State private var thumbnail: UIImage?

    var body: some View {
        let title = card.title.isEmpty ? "(untitled)" : card.title
        HStack(spacing: 12) {
            switch card.state {
            case .unlocked:
                if !card.photos.isEmpty {
                    thumbnailView
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("✅ \(title)")
                    Text("Opened")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .sealed:
                VStack(alignment: .leading, spacing: 4) {
                    Text("🔒 \(title)")
                    Text("Locked until \(unlockText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .draft:
                EmptyView()
            }
        }
        .task(id: card.id) {
            // Load a thumbnail ONLY for unlocked cards — a sealed card must never
            // touch its photo bytes (§5.3.2).
            guard card.state == .unlocked,
                  thumbnail == nil,
                  let first = card.photos.min(by: { $0.order < $1.order })
            else { return }
            if let data = photoStore.loadData(fileName: first.fileName) {
                thumbnail = UIImage(data: data)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 55)
                .clipped()
        } else {
            Rectangle()
                .fill(.gray.opacity(0.3))
                .frame(width: 44, height: 55)
        }
    }

    private var unlockText: String {
        guard let date = card.unlockDate else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Locked-card delete confirmation (§5.3)

/// Identifiable wrapper so the locked-delete sheet is driven by the domain id,
/// not SwiftData's `persistentModelID`.
private struct DeleteTarget: Identifiable {
    let id: UUID
    let card: Postcard
}

/// Identifiable wrapper for the notification-tap deep link.
private struct DeepLinkTarget: Identifiable {
    let id: UUID
    let card: Postcard
}

/// The §5.3 locked-card confirmation: shows the title and unlock date, states
/// plainly that the contents won't be seen first, and requires a press-and-hold
/// (not a tap) to actually delete.
private struct LockedDeleteConfirmView: View {

    let card: Postcard
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isPressing = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Delete “\(card.title.isEmpty ? "(untitled)" : card.title)”?")
                .font(.headline)
                .multilineTextAlignment(.center)

            if let date = card.unlockDate {
                Text("Unlocks \(date.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }

            Text("You won’t be able to see what’s inside first. This can’t be undone.")
                .multilineTextAlignment(.center)

            Text(isPressing ? "Keep holding…" : "Press and hold to delete")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Hold to delete")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(.red))
                .scaleEffect(isPressing ? 0.97 : 1)
                .onLongPressGesture(minimumDuration: 1.0, pressing: { pressing in
                    isPressing = pressing
                }, perform: onConfirm)

            Button("Cancel", role: .cancel) { onCancel() }
        }
        .padding()
        .presentationDetents([.medium])
    }
}

// MARK: - First-seal notification priming (§7.1)

private struct NotificationPrimingView: View {

    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("🔔").font(.largeTitle)
            Text("We’ll tell you when this opens")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Turn on notifications and we’ll remind you when your postcard unlocks.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Turn on notifications") { onEnable() }
                .buttonStyle(.borderedProminent)
            Button("Not now") { onSkip() }
        }
        .padding()
        .presentationDetents([.medium])
    }
}
