//
//  PostcardSurfaceView.swift
//  DearSomeday
//
//  Read-only rendering for saved postcards. The structured model remains the
//  source of truth; these views rebuild the front/back artifact from it.
//

import SwiftUI
import UIKit

struct PostcardSurfaceView: View {
    let card: Postcard
    let photosByID: [UUID: UIImage]
    let photosByOrder: [Int: UIImage]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(card: Postcard, photosByID: [UUID: UIImage], photosByOrder: [Int: UIImage] = [:]) {
        self.card = card
        self.photosByID = photosByID
        self.photosByOrder = photosByOrder
    }

    @State private var side: Side = .front

    private enum Side {
        case front
        case back
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Tap postcard to flip")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(Tokens.Color.chromeText)
                .frame(maxWidth: PostcardCanvasMetrics.maxWidth, alignment: .leading)

            PostcardFlipView(angle: side == .front ? 0 : 180) {
                PostcardFrontView(
                    card: card,
                    photosByID: photosByID,
                    photosByOrder: photosByOrder
                )
            } back: {
                PostcardBackView(card: card)
            }
                .aspectRatio(PostcardCanvasMetrics.aspectRatio, contentMode: .fit)
                .frame(maxWidth: PostcardCanvasMetrics.maxWidth)
                .contentShape(Rectangle())
                .onTapGesture { toggleSide() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(side == .front ? "Postcard front" : "Postcard back")
                .accessibilityHint("Tap to show the other side")

            metadata
                .frame(maxWidth: PostcardCanvasMetrics.maxWidth, alignment: .leading)
                .padding(.top, Tokens.Space.sm)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                Text("Title: \(title)")
            }

            Text("Postmarked: \(card.createdAt.formatted(date: .abbreviated, time: .shortened))")

            if let date = card.unlockDate {
                Text("Delivered: \(date.formatted(date: .abbreviated, time: .shortened))")
            }

            if let location = card.locationLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !location.isEmpty {
                Text("Sent from: \(location)")
            }
        }
        .font(Tokens.Font.caption)
        .foregroundStyle(Tokens.Color.chromeText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleSide() {
        let updateSide = {
            side = (side == .front) ? .back : .front
        }

        if reduceMotion {
            updateSide()
        } else {
            withAnimation(Tokens.Motion.playful) {
                updateSide()
            }
        }
    }
}

/// Renders only the face currently pointing toward the viewer. Swapping the
/// content at 90 degrees keeps the postcard back upright instead of mirrored.
private struct PostcardFlipView<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    init(
        angle: Double,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.angle = angle
        self.front = front()
        self.back = back()
    }

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            if angle <= 90 {
                front
            } else {
                back
                    .rotation3DEffect(
                        .degrees(180),
                        axis: (x: 0, y: 1, z: 0)
                    )
            }
        }
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.45
        )
    }
}

struct PostcardFrontView: View {
    let card: Postcard
    let photosByID: [UUID: UIImage]
    let photosByOrder: [Int: UIImage]

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

                if template.slotCount > 1 {
                    PostcardPhotoBarriers(template: template)
                }
            }
            .overlay(
                Rectangle().stroke(
                    Tokens.Color.paperTan.opacity(0.7),
                    lineWidth: template.slotCount > 1 ? 0 : 1
                )
            )
            .clipped()
        }
    }

    private func slotView(_ slot: TemplateSlot, in size: CGSize) -> some View {
        let slotSize = CGSize(
            width: CGFloat(slot.width) * size.width,
            height: CGFloat(slot.height) * size.height
        )
        let targetAspect = slotSize.height > 0 ? slotSize.width / slotSize.height : 1
        let assignment = assignmentsBySlot[slot.id]
        let image = image(for: assignment)
        let imageAspect = image.map { image in
            image.size.height > 0 ? image.size.width / image.size.height : targetAspect
        } ?? targetAspect
        let crop = (assignment?.crop ?? .centered).constrained(
            sourceAspect: imageAspect,
            targetAspect: targetAspect
        )

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
                ZStack {
                    Rectangle().fill(Tokens.Color.paperTan.opacity(0.3))
                    Image(systemName: "photo")
                        .font(.system(size: min(slotSize.width, slotSize.height) * 0.16))
                        .foregroundStyle(Tokens.Color.chromeTextMuted.opacity(0.45))
                }
            }
        }
        .frame(width: slotSize.width, height: slotSize.height)
        .clipped()
        .position(
            x: CGFloat(slot.x + slot.width / 2) * size.width,
            y: CGFloat(slot.y + slot.height / 2) * size.height
        )
    }

    private func image(for assignment: SlotAssignment?) -> UIImage? {
        if let assignment, let image = photosByID[assignment.photoID] {
            return image
        }

        guard let assignment else { return nil }
        let orderedPhotos = card.photos.sorted { $0.order < $1.order }
        guard let fallbackIndex = orderedPhotos.firstIndex(where: { $0.id == assignment.photoID }) else {
            return nil
        }

        return photosByOrder[orderedPhotos[fallbackIndex].order] ?? photosByOrder[fallbackIndex]
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

    private var storedFontPointSize: CGFloat? {
        PostcardRenderResolver.backFontPointSize(for: card)
    }

    private var textColor: Color {
        Color(hex: PostcardRenderResolver.backTextColorHex(for: card))
    }

    private var stamp: StampOption? {
        PostcardRenderResolver.stamp(for: card)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Image(stamp == nil ? "PostcardBack" : "PostcardBackBlank")
                    .resizable()
                    .aspectRatio(PostcardCanvasMetrics.aspectRatio, contentMode: .fit)

                if !text.isEmpty {
                    PostcardMessageTextView(
                        text: .constant(text),
                        font: storedFontPointSize.map(font.uiFont(pointSize:)) ?? font.uiBodyFont,
                        textColor: UIColor(textColor),
                        isEditable: false,
                        adaptiveMinimumPointSize: storedFontPointSize == nil
                            ? PostcardBackFont.minimumLegacyPointSize
                            : nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }

                if let stamp {
                    let frame = PostcardBackLayout.stampFrame(in: proxy.size)
                    PostcardPlacedStampImage(
                        option: stamp,
                        size: frame.size
                    )
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel(stamp.accessibilityLabel)
                }
            }
            .overlay(Rectangle().stroke(Tokens.Color.paperTan.opacity(0.7), lineWidth: 1))
            .clipped()
        }
    }
}
