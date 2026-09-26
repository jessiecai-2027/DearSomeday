//
//  PostcardTimelineView.swift
//  DearFutureMe
//
//  Envelope timeline with shared paper texture. Locked cards never load photo
//  bytes; unlocked cards open through the display view's trusted-time check.
//  Maintains unlock sweeps, paging, deletion, and notification routing.

import SwiftUI
import UIKit

struct PostcardTimelineView: View {

    let services: AppServices

    /// §5.5 batch size.
    private static let pageSize = 50
    /// Keep due cards current while the mailbox remains onscreen. This pass
    /// uses the projected trusted clock and does not make a network request.
    private static let unlockCheckInterval: Duration = .seconds(1)
    /// §7.1: prime once, after the first seal.
    private static let primedKey = "hasPrimedNotifications"

    @Environment(\.scenePhase) private var scenePhase

    @State private var cards: [Postcard] = []
    @State private var canLoadMore = false
    @State private var isBusy = false
    @State private var isLoadingPage = false
    @State private var timelineOffset = 0
    @State private var timelineFilter: PostcardTimelineFilter = .all
    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    @FocusState private var isSearchFieldFocused: Bool

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
                        .timelineForegroundShadow()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: Tokens.Space.xs,
                            leading: Tokens.Space.screenMargin,
                            bottom: Tokens.Space.xs,
                            trailing: Tokens.Space.screenMargin
                        ))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                requestDelete(card)
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(Tokens.Font.button)
                            }
                        }
                        .onAppear { maybeLoadMore(after: card) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                AppBackgroundView()
            }
            .overlay {
                if cards.isEmpty && !isBusy {
                    emptyState
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: Tokens.Space.xs) {
                    if notificationsDenied {
                        deniedBanner
                    }
                    mailboxHeader
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
                .font(Tokens.Font.button)
                Button("Cancel", role: .cancel) { unlockedDeleteTarget = nil }
                    .font(Tokens.Font.button)
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
        .onChange(of: timelineFilter) {
            Task { await reload() }
        }
        .onChange(of: searchQuery) {
            Task { await reload() }
        }
        // Sync once on launch, then keep due cards current while the mailbox is
        // onscreen. The scenePhase handler refreshes trusted time after every
        // later foreground transition.
        .task {
            await sweepAndReload()
            await monitorForDueCards()
        }
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
            Button {
                deepLink = DeepLinkTarget(id: card.id, card: card)
            } label: {
                TimelineRowView(card: card)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this postcard")
        } else {
            // Taps explain the lock without opening or loading postcard contents.
            LockedTimelineRow(card: card)
        }
    }

    private var emptyState: some View {
        let isSearching = !PostcardTimelineSearch.normalizedQuery(searchQuery).isEmpty

        return VStack(spacing: Tokens.Space.md) {
            if isSearching {
                Text("No matching postcards.")
                    .font(Tokens.Font.headline)
                Text("Try a different title or message.")
                    .foregroundStyle(Tokens.Color.chromeText)
                Button {
                    searchQuery = ""
                    isSearchFieldFocused = true
                } label: {
                    Text("Clear search")
                        .font(Tokens.Font.button)
                        .foregroundStyle(Tokens.Color.paperCream)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(timelineFilter.emptyTitle).font(Tokens.Font.headline)
                Text(timelineFilter.emptyMessage)
                    .foregroundStyle(Tokens.Color.chromeText)
                Button { showComposer = true } label: {
                    Text("Create a postcard")
                        .font(Tokens.Font.button)
                        .foregroundStyle(Tokens.Color.paperCream)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .multilineTextAlignment(.center)
        .timelineForegroundShadow()
    }

    private var mailboxHeader: some View {
        VStack(spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.sm) {
                Text("Mailbox")
                    .font(Tokens.Font.screenTitle)
                    .foregroundStyle(Tokens.Color.inkEspresso)
                    .lineLimit(1)
                    .timelineForegroundShadow()

                Spacer(minLength: Tokens.Space.xs)

                /*
                #if DEBUG
                // Debug utilities retained here for future development builds.
                Menu {
                    Button("Sweep") { Task { await sweepAndReload() } }
                    Button("Seed 20s") { Task { await seedDebugCard() } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Debug tools")
                #endif
                */

                Button { presentSearch() } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 28, height: 28)
                        .timelineForegroundShadow()
                }
                .accessibilityLabel("Search postcards")
                .accessibilityAddTraits(isSearchPresented ? .isSelected : [])

                Button { showComposer = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .timelineForegroundShadow()
                }
                .accessibilityLabel("New postcard")

                filterControl
            }

            if isSearchPresented {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .screenMargins()
        .padding(.top, Tokens.Space.xxs)
        .padding(.bottom, Tokens.Space.sm)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Tokens.Color.paperCream.opacity(0.48)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Tokens.Color.chromeTextMuted)

                TextField("Search titles and messages", text: $searchQuery)
                    .font(Tokens.Font.body)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFieldFocused = false }

                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Tokens.Color.chromeTextMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Tokens.Space.sm)
            .padding(.vertical, Tokens.Space.xs)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.subtle))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.subtle)
                    .stroke(Tokens.Color.chromeDivider.opacity(0.7), lineWidth: 0.5)
            }

            Button("Cancel") { dismissSearch() }
                .font(Tokens.Font.button)
                .foregroundStyle(Tokens.Color.inkEspresso)
        }
        .timelineForegroundShadow()
    }

    private func presentSearch() {
        guard !isSearchPresented else {
            isSearchFieldFocused = true
            return
        }

        withAnimation(Tokens.Motion.subtle) {
            isSearchPresented = true
        }
        Task { @MainActor in
            await Task.yield()
            isSearchFieldFocused = true
        }
    }

    private func dismissSearch() {
        isSearchFieldFocused = false
        searchQuery = ""
        withAnimation(Tokens.Motion.subtle) {
            isSearchPresented = false
        }
    }

    private var filterControl: some View {
        HStack(spacing: Tokens.Space.xxs) {
            ForEach(PostcardTimelineFilter.allCases) { filter in
                Button {
                    withAnimation(Tokens.Motion.subtle) {
                        timelineFilter = filter
                    }
                } label: {
                    Image(systemName: filter.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 28)
                        .foregroundStyle(
                            timelineFilter == filter
                                ? Tokens.Color.inkEspresso
                                : Tokens.Color.chromeTextMuted
                        )
                        .background {
                            if timelineFilter == filter {
                                Capsule().fill(Tokens.Color.paperTan.opacity(0.72))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filter.accessibilityLabel)
                .accessibilityAddTraits(timelineFilter == filter ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Tokens.Color.chromeDivider.opacity(0.7), lineWidth: 0.5)
        }
        .timelineForegroundShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline filter")
    }

    private var deniedBanner: some View {
        HStack(spacing: 8) {
            Text("Notifications are off — you won’t be reminded when a postcard opens.")
                .font(Tokens.Font.footnote)
            Spacer(minLength: 8)
            Button("Settings") { openSettings() }
                .font(Tokens.Font.button)
        }
        .timelineForegroundShadow()
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

    /// Unlocks cards as their due dates arrive while the timeline stays open.
    /// `TrustedClock.now()` advances from its server-backed anchor using system
    /// uptime, so this lightweight pass stays tamper-resistant without issuing
    /// a network request every second. App suspension cancels useful work; the
    /// foreground sweep catches up and refreshes the server anchor on return.
    private func monitorForDueCards() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.unlockCheckInterval)
            } catch {
                return
            }

            guard scenePhase == .active, !isBusy else { continue }
            let unlocked = await services.coordinator.unlockDueCards()
            guard !unlocked.isEmpty else { continue }

            await rescheduleNotifications()
            await reload()
        }
    }

    /// Resets to the first page. Called after a sweep, a compose, or a delete —
    /// any change that can reorder or shrink the list.
    private func reload() async {
        let filter = timelineFilter
        let query = PostcardTimelineSearch.normalizedQuery(searchQuery)

        if !query.isEmpty {
            let results = await searchedCards(for: filter, query: query)
            guard timelineFilter == filter,
                  PostcardTimelineSearch.normalizedQuery(searchQuery) == query else { return }

            cards = results
            timelineOffset = 0
            canLoadMore = false
            return
        }

        let page = await filteredPage(for: filter, startingAt: 0)
        guard timelineFilter == filter,
              PostcardTimelineSearch.normalizedQuery(searchQuery).isEmpty else { return }

        cards = page.cards
        timelineOffset = page.nextOffset
        canLoadMore = page.hasMore
    }

    private func maybeLoadMore(after card: Postcard) {
        guard card.id == cards.last?.id else { return }
        Task { await loadNextPage() }
    }

    private func loadNextPage() async {
        guard canLoadMore,
              !isLoadingPage,
              PostcardTimelineSearch.normalizedQuery(searchQuery).isEmpty else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let filter = timelineFilter
        let page = await filteredPage(for: filter, startingAt: timelineOffset)
        guard timelineFilter == filter,
              PostcardTimelineSearch.normalizedQuery(searchQuery).isEmpty else { return }

        cards.append(contentsOf: page.cards)
        timelineOffset = page.nextOffset
        canLoadMore = page.hasMore
    }

    /// Search must inspect the complete timeline before ranking so a title
    /// match on a later page still precedes an earlier message-only match.
    private func searchedCards(
        for filter: PostcardTimelineFilter,
        query: String
    ) async -> [Postcard] {
        var offset = 0
        var sourceCards: [Postcard] = []

        while true {
            guard timelineFilter == filter,
                  PostcardTimelineSearch.normalizedQuery(searchQuery) == query,
                  let source = try? await services.store.timeline(
                      offset: offset,
                      limit: Self.pageSize
                  ) else {
                return []
            }

            sourceCards.append(contentsOf: source)
            offset += source.count

            if source.count < Self.pageSize {
                return PostcardTimelineSearch.results(
                    in: sourceCards,
                    query: query,
                    filter: filter
                )
            }
        }
    }

    /// Reads source pages until it has a useful page for the active filter or
    /// reaches the end. This matters for "delivered": sealed cards sort first,
    /// so filtering only the first raw page could falsely show an empty list.
    private func filteredPage(
        for filter: PostcardTimelineFilter,
        startingAt initialOffset: Int
    ) async -> FilteredTimelinePage {
        var offset = initialOffset
        var matches: [Postcard] = []

        while matches.count < Self.pageSize {
            guard let source = try? await services.store.timeline(
                offset: offset,
                limit: Self.pageSize
            ) else {
                return FilteredTimelinePage(cards: matches, nextOffset: offset, hasMore: false)
            }

            offset += source.count
            matches.append(contentsOf: source.filter(filter.includes))

            if source.count < Self.pageSize {
                return FilteredTimelinePage(cards: matches, nextOffset: offset, hasMore: false)
            }
        }

        return FilteredTimelinePage(cards: matches, nextOffset: offset, hasMore: true)
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

    /*
    #if DEBUG
    /// Seals a real card 20 seconds out so automatic unlocking can be watched
    /// on device during future development.
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
    */
}

private extension View {
    func timelineForegroundShadow() -> some View {
        shadow(
            color: Tokens.Color.inkEspresso.opacity(0.22),
            radius: 1.25,
            x: 0,
            y: 1
        )
    }
}

// MARK: - Row

private struct LockedTimelineRow: View {
    let card: Postcard

    @State private var tapCount = 0
    @State private var showsFeedback = false

    var body: some View {
        Button {
            showsFeedback = true
            tapCount += 1
        } label: {
            TimelineRowView(card: card, showsLockedFeedback: showsFeedback,
                            shakeTrigger: tapCount)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows when this postcard will unlock")
        .task(id: tapCount) {
            guard tapCount > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(3))
                showsFeedback = false
            } catch {
                // A new tap restarts the message timer; leaving cancels it.
            }
        }
    }
}

private struct TimelineRowView: View {

    let card: Postcard
    var showsLockedFeedback = false
    var shakeTrigger = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.lg) {
            Image(card.state == .unlocked ? "EnvelopeOpen" : "EnvelopeClosed")
                .resizable()
                .scaledToFit()
                .envelopePaperTone()
                .frame(width: Tokens.Timeline.envelopeWidth,
                       height: Tokens.Timeline.envelopeHeight)
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeTrigger) { content, offset in
                    content.offset(x: reduceMotion ? 0 : offset)
                } keyframes: { _ in
                    CubicKeyframe(-Tokens.Timeline.shakeDistance, duration: 0.08)
                    CubicKeyframe(Tokens.Timeline.shakeDistance, duration: 0.10)
                    CubicKeyframe(-Tokens.Timeline.shakeDistance / 2, duration: 0.09)
                    CubicKeyframe(Tokens.Timeline.shakeDistance / 2, duration: 0.08)
                    CubicKeyframe(0, duration: 0.10)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                TimelineTitle(text: card.title.isEmpty ? "(untitled)" : card.title)
                Text(showsLockedFeedback ? "Still sealed until \(unlockText)" : "Unlock date: \(unlockText)")
                    .font(Tokens.Font.timelineDate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Tokens.Color.inkEspresso)
        .frame(maxWidth: Tokens.Timeline.maxRowWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(card.state == .unlocked ? "Unlocked" : "Locked")
    }

    private var unlockText: String {
        guard let date = card.unlockDate else { return "—" }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits).hour().minute())
    }
}

/// Truncates at a word boundary so the second line never ends with half a word.
private struct TimelineTitle: UIViewRepresentable {
    let text: String
    @ScaledMetric(relativeTo: .title2) private var fontSize = Tokens.Font.timelineTitleSize

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.font = UIFont(name: Tokens.Font.Family.display, size: fontSize)
            ?? .systemFont(ofSize: fontSize)
        label.textColor = UIColor(Tokens.Color.inkEspresso)
        label.text = text
        label.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let font = label.font!
        let maxHeight = ceil(font.lineHeight * 2)
        func height(of value: String) -> CGFloat {
            ceil((value as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font], context: nil
            ).height)
        }

        var displayed = text
        if height(of: text) > maxHeight {
            let words = text.split(whereSeparator: \.isWhitespace)
            var lower = 0
            var upper = words.count
            while lower < upper {
                let count = (lower + upper + 1) / 2
                let candidate = words.prefix(count).joined(separator: " ") + "…"
                if height(of: candidate) <= maxHeight {
                    lower = count
                } else {
                    upper = count - 1
                }
            }
            displayed = words.prefix(lower).joined(separator: " ") + "…"
        }
        label.text = displayed
        return CGSize(width: width, height: min(height(of: displayed), maxHeight))
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

private struct FilteredTimelinePage {
    let cards: [Postcard]
    let nextOffset: Int
    let hasMore: Bool
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
                .font(Tokens.Font.headline)
                .multilineTextAlignment(.center)

            if let date = card.unlockDate {
                Text("Unlocks \(date.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(Tokens.Color.chromeText)
            }

            Text("You won’t be able to see what’s inside first. This can’t be undone.")
                .multilineTextAlignment(.center)

            Text(isPressing ? "Keep holding…" : "Press and hold to delete")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.chromeText)

            Text("Hold to delete")
                .font(Tokens.Font.button)
                .foregroundStyle(Tokens.Color.chromeText)
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(.red))
                .scaleEffect(isPressing ? 0.97 : 1)
                .onLongPressGesture(minimumDuration: 1.0, pressing: { pressing in
                    isPressing = pressing
                }, perform: onConfirm)

            Button("Cancel", role: .cancel) { onCancel() }
                .font(Tokens.Font.button)
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
            Image(systemName: "bell").font(.largeTitle)
                .accessibilityHidden(true)
            Text("We’ll tell you when this opens")
                .font(Tokens.Font.headline)
                .multilineTextAlignment(.center)
            Text("Turn on notifications and we’ll remind you when your postcard unlocks.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.Color.chromeText)
            Button("Turn on notifications") { onEnable() }
                .font(Tokens.Font.button)
                .buttonStyle(.borderedProminent)
            Button("Not now") { onSkip() }
                .font(Tokens.Font.button)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
