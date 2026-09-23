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
}

enum StampCatalog {
    static let all: [StampOption] = [
        StampOption(id: "golden-flower", imageName: "StampGoldenFlower", accessibilityLabel: "Golden flower stamp"),
        StampOption(id: "purple-wildflower", imageName: "StampPurpleWildflower", accessibilityLabel: "Purple wildflower stamp"),
        StampOption(id: "pink-daisies", imageName: "StampPinkDaisies", accessibilityLabel: "Pink daisies stamp"),
        StampOption(id: "mushroom", imageName: "StampMushroom", accessibilityLabel: "Mushroom stamp"),
        StampOption(id: "grapes", imageName: "StampGrapes", accessibilityLabel: "Grapes stamp"),
        StampOption(id: "robin", imageName: "StampRobin", accessibilityLabel: "Robin stamp"),
        StampOption(id: "sailboat", imageName: "StampSailboat", accessibilityLabel: "Sailboat stamp"),
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
        .presentationCompactAdaptation(.popover)
    }
}
