//
//  PostcardSurfaceView.swift
//  DearFutureMe
//
//  Read-only rendering for saved postcards. The structured model remains the
//  source of truth; these views rebuild the front/back artifact from it.
//

import SwiftUI
import UIKit

struct PostcardSurfaceView: View {
    let card: Postcard
    let photosByID: [UUID: UIImage]

    @State private var side: Side = .front

    private enum Side {
        case front
        case back
    }

    var body: some View {
        VStack(spacing: 10) {
            Group {
                switch side {
                case .front:
                    PostcardFrontView(card: card, photosByID: photosByID)
                case .back:
                    PostcardBackView(card: card)
                }
            }
            .aspectRatio(PostcardCanvasMetrics.aspectRatio, contentMode: .fit)
            .frame(maxWidth: PostcardCanvasMetrics.maxWidth)
            .contentShape(Rectangle())
            .onTapGesture { toggleSide() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(side == .front ? "Postcard front" : "Postcard back")
            .accessibilityHint("Tap to show the other side")

            Text(side == .front ? "Front" : "Back")
                .font(Tokens.Font.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleSide() {
        withAnimation(.snappy(duration: 0.2)) {
            side = (side == .front) ? .back : .front
        }
    }
}

struct PostcardFrontView: View {
    let card: Postcard
    let photosByID: [UUID: UIImage]

    private var template: CardTemplate {
        PostcardRenderResolver.template(for: card)
    }

    private var assignmentsBySlot: [String: SlotAssignment] {
        let assignments = PostcardRenderResolver.assignments(for: card, template: template)
        return Dictionary(uniqueKeysWithValues: assignments.map { ($0.slotID, $0) })
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Tokens.Color.paperCream)

                ForEach(template.slots) { slot in
                    slotView(slot, in: proxy.size)
                }
            }
            .overlay(Rectangle().stroke(Tokens.Color.paperTan.opacity(0.7), lineWidth: 1))
            .clipped()
        }
    }

    private func slotView(_ slot: TemplateSlot, in size: CGSize) -> some View {
        let slotSize = CGSize(
            width: CGFloat(slot.width) * size.width,
            height: CGFloat(slot.height) * size.height
        )
        let assignment = assignmentsBySlot[slot.id]
        let image = assignment.flatMap { photosByID[$0.photoID] }
        let crop = assignment?.crop ?? .centered

        return ZStack {
            Rectangle().fill(.white)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: slotSize.width * CGFloat(crop.scale),
                        height: slotSize.height * CGFloat(crop.scale)
                    )
                    .offset(
                        x: CGFloat(crop.offsetX) * slotSize.width,
                        y: CGFloat(crop.offsetY) * slotSize.height
                    )
            } else {
                Rectangle().fill(Tokens.Color.paperTan.opacity(0.3))
            }
        }
        .frame(width: slotSize.width, height: slotSize.height)
        .clipped()
        .overlay(Rectangle().stroke(.white, lineWidth: template.slotCount > 1 ? 3 : 0))
        .position(
            x: CGFloat(slot.x + slot.width / 2) * size.width,
            y: CGFloat(slot.y + slot.height / 2) * size.height
        )
    }
}

struct PostcardBackView: View {
    let card: Postcard

    private var text: String {
        card.backText.isEmpty ? card.message : card.backText
    }

    private var font: PostcardBackFont {
        PostcardRenderResolver.backFont(for: card)
    }

    private var textColor: Color {
        Color(hex: PostcardRenderResolver.backTextColorHex(for: card))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Image("PostcardBack")
                    .resizable()
                    .scaledToFit()

                VStack(alignment: .leading, spacing: scaled(12, in: proxy.size)) {
                    if !text.isEmpty {
                        Text(text)
                            .font(font.bodyFont)
                            .foregroundStyle(textColor)
                            .lineSpacing(6)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: scaled(8, in: proxy.size))

                    metadata
                }
                .padding(.horizontal, scaled(32, in: proxy.size))
                .padding(.top, scaled(42, in: proxy.size))
                .padding(.bottom, scaled(28, in: proxy.size))
            }
            .overlay(Rectangle().stroke(Tokens.Color.paperTan.opacity(0.7), lineWidth: 1))
            .clipped()
        }
    }

    @ViewBuilder
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let location = card.locationLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !location.isEmpty {
                Text("Place: \(location)")
            }

            Text("Created \(card.createdAt.formatted(date: .abbreviated, time: .omitted))")

            if let date = card.unlockDate {
                Text("Unlocked \(date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .font(Tokens.Font.caption)
        .foregroundStyle(Tokens.Color.inkEspresso.opacity(0.72))
    }

    private func scaled(_ value: CGFloat, in size: CGSize) -> CGFloat {
        value * min(size.width / PostcardCanvasMetrics.maxWidth, 1)
    }
}
