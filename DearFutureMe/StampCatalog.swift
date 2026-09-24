//
//  StampCatalog.swift
//  DearFutureMe
//
//  Stable, app-owned identities for the postcard stamp catalog.
//

import SwiftUI

struct StampOption: Identifiable, Equatable, Hashable {
    let id: String
    let imageName: String
    let accessibilityLabel: String
    let sourceSize: CGSize

    func placementCovering(_ frame: CGRect) -> (size: CGSize, center: CGPoint) {
        let sourceAspectRatio = sourceSize.width / sourceSize.height
        let frameAspectRatio = frame.width / frame.height
        let size: CGSize

        if sourceAspectRatio >= frameAspectRatio {
            size = CGSize(
                width: frame.height * sourceAspectRatio,
                height: frame.height
            )
        } else {
            size = CGSize(
                width: frame.width,
                height: frame.width / sourceAspectRatio
            )
        }

        return (
            size,
            CGPoint(
                x: frame.minX + size.width / 2,
                y: frame.maxY - size.height / 2
            )
        )
    }
}

enum StampCatalog {
    static let all: [StampOption] = [
        StampOption(id: "golden-flower", imageName: "StampGoldenFlower", accessibilityLabel: "Golden flower stamp", sourceSize: CGSize(width: 866, height: 866)),
        StampOption(id: "purple-wildflower", imageName: "StampPurpleWildflower", accessibilityLabel: "Purple wildflower stamp", sourceSize: CGSize(width: 941, height: 941)),
        StampOption(id: "pink-daisies", imageName: "StampPinkDaisies", accessibilityLabel: "Pink daisies stamp", sourceSize: CGSize(width: 575, height: 575)),
        StampOption(id: "mushroom", imageName: "StampMushroom", accessibilityLabel: "Mushroom stamp", sourceSize: CGSize(width: 641, height: 641)),
        StampOption(id: "grapes", imageName: "StampGrapes", accessibilityLabel: "Grapes stamp", sourceSize: CGSize(width: 600, height: 600)),
        StampOption(id: "robin", imageName: "StampRobin", accessibilityLabel: "Robin stamp", sourceSize: CGSize(width: 434, height: 471)),
        StampOption(id: "sailboat", imageName: "StampSailboat", accessibilityLabel: "Sailboat stamp", sourceSize: CGSize(width: 309, height: 387)),
    ]

    static func option(withID id: String?) -> StampOption? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

struct PostcardStampImage: View {
    let option: StampOption

    var body: some View {
        Image(option.imageName)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct PostcardPlacedStampImage: View {
    let option: StampOption
    let size: CGSize

    var body: some View {
        let bounds = CGRect(origin: .zero, size: size)
        let placement = option.placementCovering(bounds)

        ZStack(alignment: .topLeading) {
            PostcardStampImage(option: option)
                .frame(
                    width: placement.size.width,
                    height: placement.size.height
                )
                .position(
                    x: placement.center.x,
                    y: placement.center.y
                )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

struct StampPopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct StampPickerPopover: View {
    let selectedStampID: String?
    let onSelect: (StampOption) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Tokens.Space.sm),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text("Choose a Stamp")
                .font(Tokens.Font.headline)

            LazyVGrid(columns: columns, spacing: Tokens.Space.sm) {
                ForEach(StampCatalog.all) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            PostcardStampImage(option: option)
                                .padding(Tokens.Space.xs)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)

                            if selectedStampID == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .blue)
                                    .font(.system(size: 20, weight: .semibold))
                                    .padding(Tokens.Space.xxs)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.subtle)
                                .fill(Tokens.Color.paperCream.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.subtle)
                                .stroke(
                                    selectedStampID == option.id ? Color.blue : Tokens.Color.chromeDivider,
                                    lineWidth: selectedStampID == option.id ? 3 : 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.subtle))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                    .accessibilityValue(selectedStampID == option.id ? "Selected" : "")
                    .accessibilityAddTraits(selectedStampID == option.id ? .isSelected : [])
                }
            }
        }
        .padding(Tokens.Space.md)
        .frame(width: 264)
    }
}
