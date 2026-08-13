//
//  PostcardTimelineView.swift
//  DearFutureMe
//
//  The app's root, replacing the token-test ContentView. **Intentionally ugly**
//  (BUILD-PLAN step 3): system List, no textures, no Tokens. Its only jobs right
//  now are (1) run the unlock sweep on launch and every foreground, and (2) show
//  the timeline so the sweep's effect is visible. The scrapbook look is step 4.
//
//  Sealed rows show the title only — never photos or the message (§5.3.2). The
//  contents simply aren't loaded, which is the strongest form of "not revealed".
//

import SwiftUI

struct PostcardTimelineView: View {

    let services: AppServices

    @Environment(\.scenePhase) private var scenePhase
    @State private var cards: [Postcard] = []
    @State private var isBusy = false
    @State private var showComposer = false

    var body: some View {
        NavigationStack {
            List {
                if cards.isEmpty {
                    Text("No postcards yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(cards, id: \.id) { card in
                    row(for: card)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sweep") { Task { await sweepAndReload() } }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Seed 20s") { Task { await seedDebugCard() } }
                }
            }
            #endif
        }
        .sheet(isPresented: $showComposer, onDismiss: { Task { await reload() } }) {
            ComposerView(services: services)
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
    private func row(for card: Postcard) -> some View {
        let title = card.title.isEmpty ? "(untitled)" : card.title
        VStack(alignment: .leading, spacing: 4) {
            switch card.state {
            case .sealed:
                Text("🔒 \(title)")
                Text("Locked until \(unlockText(card))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unlocked:
                Text("✅ \(title)")
                Text("Opened")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .draft:
                EmptyView()     // drafts never reach the timeline
            }
        }
    }

    // MARK: - Sweep + reload

    /// Runs the launch/foreground sweep, then refreshes the list. The `isBusy`
    /// guard collapses the near-simultaneous launch `.task` and first `.active`
    /// transition into one pass, and prevents overlapping sweeps from racing.
    private func sweepAndReload() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        await services.coordinator.runSweep()
        await reload()
    }

    private func reload() async {
        cards = (try? await services.store.timeline(offset: 0, limit: 50)) ?? []
    }

    private func unlockText(_ card: Postcard) -> String {
        guard let date = card.unlockDate else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Debug seeding (removed before release, like the §5.7 test button)

    #if DEBUG
    /// Seals a real card 20 seconds out so the sweep can be watched on device
    /// without the composer: background/foreground (or tap Sweep) after 20s and
    /// it flips to ✅. Uses the real seal + trusted-time path, not a shortcut.
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
