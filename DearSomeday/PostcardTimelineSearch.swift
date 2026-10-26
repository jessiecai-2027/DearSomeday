//
//  PostcardTimelineSearch.swift
//  DearSomeday
//
//  Privacy-aware mailbox search. Sealed-card messages are intentionally never
//  inspected: even a yes/no match would reveal information before unlock.

import Foundation

enum PostcardTimelineSearch {

    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns only matching cards. Title matches form the first stable group;
    /// message-only matches form the second, preserving input order in each.
    static func results(
        in cards: [Postcard],
        query: String,
        filter: PostcardTimelineFilter
    ) -> [Postcard] {
        let query = normalizedQuery(query)
        guard !query.isEmpty else {
            return cards.filter(filter.includes)
        }

        var titleMatches: [Postcard] = []
        var messageMatches: [Postcard] = []

        for card in cards where filter.includes(card) {
            if contains(card.title, query: query) {
                titleMatches.append(card)
            } else if card.state == .unlocked,
                      contains(searchableMessage(for: card), query: query) {
                messageMatches.append(card)
            }
        }

        return titleMatches + messageMatches
    }

    private static func searchableMessage(for card: Postcard) -> String {
        card.backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? card.message
            : card.backText
    }

    private static func contains(_ text: String, query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return text.range(of: query, options: options, locale: .current) != nil
    }
}
