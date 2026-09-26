import Testing
@testable import DearFutureMe

@MainActor
struct PostcardTimelineFilterTests {

    @Test func filtersCardsByDeliveryState() {
        let draft = Postcard(state: .draft)
        let sealed = Postcard(state: .sealed)
        let delivered = Postcard(state: .unlocked)

        #expect(!PostcardTimelineFilter.all.includes(draft))
        #expect(PostcardTimelineFilter.all.includes(sealed))
        #expect(PostcardTimelineFilter.all.includes(delivered))

        #expect(PostcardTimelineFilter.sealed.includes(sealed))
        #expect(!PostcardTimelineFilter.sealed.includes(delivered))

        #expect(PostcardTimelineFilter.delivered.includes(delivered))
        #expect(!PostcardTimelineFilter.delivered.includes(sealed))
    }
}

@MainActor
struct PostcardTimelineSearchTests {

    @Test func ranksTitleMatchesBeforeMessageMatchesAndPreservesGroupOrder() {
        let firstMessage = Postcard(title: "One", backText: "Autumn trip", state: .unlocked)
        let firstTitle = Postcard(title: "Trip planning", backText: "One", state: .unlocked)
        let secondMessage = Postcard(title: "Two", backText: "Trip memories", state: .unlocked)
        let secondTitle = Postcard(title: "A later trip", backText: "Two", state: .unlocked)

        let results = PostcardTimelineSearch.results(
            in: [firstMessage, firstTitle, secondMessage, secondTitle],
            query: "trip",
            filter: .all
        )

        #expect(results.map(\.id) == [firstTitle.id, secondTitle.id, firstMessage.id, secondMessage.id])
    }

    @Test func excludesNonMatchesAndDoesNotDuplicateCardsMatchingBothFields() {
        let both = Postcard(title: "Iceland", backText: "Iceland was beautiful", state: .unlocked)
        let neither = Postcard(title: "Home", backText: "A quiet weekend", state: .unlocked)

        let results = PostcardTimelineSearch.results(
            in: [both, neither],
            query: "Iceland",
            filter: .all
        )

        #expect(results.map(\.id) == [both.id])
    }

    @Test func matchingIsCaseAndDiacriticInsensitive() {
        let titleMatch = Postcard(title: "CAFÉ NOTES", state: .sealed)
        let messageMatch = Postcard(title: "Elsewhere", backText: "Résumé thoughts", state: .unlocked)

        #expect(PostcardTimelineSearch.results(
            in: [titleMatch], query: "cafe", filter: .all
        ).map(\.id) == [titleMatch.id])
        #expect(PostcardTimelineSearch.results(
            in: [messageMatch], query: "RESUME", filter: .all
        ).map(\.id) == [messageMatch.id])
    }

    @Test func sealedCardsNeverMatchMessageContent() {
        let sealed = Postcard(title: "Private", message: "secret phrase", backText: "secret phrase", state: .sealed)
        let unlocked = Postcard(title: "Open", backText: "secret phrase", state: .unlocked)

        let results = PostcardTimelineSearch.results(
            in: [sealed, unlocked], query: "secret", filter: .all
        )

        #expect(results.map(\.id) == [unlocked.id])
    }

    @Test func unlockedCardsUseBackTextThenLegacyMessageFallback() {
        let current = Postcard(message: "not selected", backText: "current copy", state: .unlocked)
        let legacy = Postcard(message: "legacy copy", backText: "  ", state: .unlocked)

        #expect(PostcardTimelineSearch.results(
            in: [current, legacy], query: "copy", filter: .all
        ).map(\.id) == [current.id, legacy.id])
        #expect(PostcardTimelineSearch.results(
            in: [current], query: "not selected", filter: .all
        ).isEmpty)
    }

    @Test func combinesSearchWithDeliveryFilter() {
        let sealed = Postcard(title: "Trip locked", state: .sealed)
        let delivered = Postcard(title: "Trip open", state: .unlocked)

        #expect(PostcardTimelineSearch.results(
            in: [sealed, delivered], query: "trip", filter: .sealed
        ).map(\.id) == [sealed.id])
        #expect(PostcardTimelineSearch.results(
            in: [sealed, delivered], query: "trip", filter: .delivered
        ).map(\.id) == [delivered.id])
    }

    @Test func blankQueryReturnsFilteredCardsWithoutReordering() {
        let delivered = Postcard(title: "Open", state: .unlocked)
        let sealed = Postcard(title: "Locked", state: .sealed)

        let results = PostcardTimelineSearch.results(
            in: [delivered, sealed], query: " \n ", filter: .all
        )

        #expect(results.map(\.id) == [delivered.id, sealed.id])
    }
}
