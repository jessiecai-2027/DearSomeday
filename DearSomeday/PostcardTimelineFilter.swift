//
//  PostcardTimelineFilter.swift
//  DearSomeday
//
//  The three compact views available from the mailbox timeline.
//

enum PostcardTimelineFilter: String, CaseIterable, Identifiable {
    case all
    case sealed
    case delivered

    var id: Self { self }

    func includes(_ card: Postcard) -> Bool {
        switch self {
        case .all:
            card.state != .draft
        case .sealed:
            card.state == .sealed
        case .delivered:
            card.state == .unlocked
        }
    }

    var symbolName: String {
        switch self {
        case .all: "rectangle.stack.fill"
        case .sealed: "envelope.fill"
        case .delivered: "envelope.open.fill"
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .sealed: "Sealed"
        case .delivered: "Delivered"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .all: "All postcards"
        case .sealed: "Sealed postcards"
        case .delivered: "Delivered postcards"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "No postcards yet."
        case .sealed: "No sealed postcards."
        case .delivered: "No delivered postcards."
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "Write one to your future self."
        case .sealed: "Newly sealed postcards will appear here."
        case .delivered: "Postcards appear here once they open."
        }
    }
}
