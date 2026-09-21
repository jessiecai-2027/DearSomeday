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
