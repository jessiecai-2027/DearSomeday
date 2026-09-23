import Testing
import UIKit
@testable import DearFutureMe

@MainActor
struct PostcardMessageLayoutTests {
    private let canvasSize = CGSize(
        width: PostcardCanvasMetrics.maxWidth,
        height: PostcardCanvasMetrics.maxWidth / PostcardCanvasMetrics.aspectRatio
    )

    @Test func ordinaryTextFitsButExcessiveReturnsDoNot() {
        let font = PostcardBackFont.caveat.uiFont(pointSize: 17)

        #expect(PostcardMessageLayout.fits(
            "A short note from today.",
            font: font,
            canvasSize: canvasSize
        ))
        #expect(!PostcardMessageLayout.fits(
            String(repeating: "\n", count: 100),
            font: font,
            canvasSize: canvasSize
        ))
    }

    @Test func longUnbrokenAndEmojiHeavyTextRespectTheBoundary() {
        let font = PostcardBackFont.caveat.uiFont(pointSize: 17)

        #expect(!PostcardMessageLayout.fits(
            String(repeating: "W", count: 5_000),
            font: font,
            canvasSize: canvasSize
        ))
        #expect(!PostcardMessageLayout.fits(
            String(repeating: "🌻", count: 2_000),
            font: font,
            canvasSize: canvasSize
        ))
    }

    @Test func unusedFontFindsALockedSizeBetweenTwelveAndSeventeen() throws {
        let font = PostcardBackFont.ebGaramond
        var text = "A memory worth keeping "
        while PostcardMessageLayout.fits(
            text,
            font: font.uiFont(pointSize: 17),
            canvasSize: canvasSize
        ) {
            text += "A memory worth keeping "
        }

        let size = try #require(PostcardMessageLayout.largestFittingPointSize(
            for: text,
            font: font,
            canvasSize: canvasSize
        ))
        #expect(size >= 12)
        #expect(size < 17)
        #expect(PostcardMessageLayout.fits(
            text,
            font: font.uiFont(pointSize: size),
            canvasSize: canvasSize
        ))
    }

    @Test func fontIsUnavailableWhenTextCannotFitAtTwelvePoints() {
        let size = PostcardMessageLayout.largestFittingPointSize(
            for: String(repeating: "\n", count: 100),
            font: .josefinSans,
            canvasSize: canvasSize
        )

        #expect(size == nil)
    }

    @Test func pasteKeepsOnlyTheLongestFittingPrefixAcrossLockedFonts() {
        let currentText = "Beginning: "
        let replacement = String(repeating: "wide words 🌻 ", count: 300)
        let fonts = [
            PostcardBackFont.caveat.uiFont(pointSize: 17),
            PostcardBackFont.ebGaramond.uiFont(pointSize: 13)
        ]
        let accepted = PostcardMessageLayout.longestFittingReplacement(
            in: currentText,
            replacing: currentText.endIndex..<currentText.endIndex,
            with: replacement,
            fonts: fonts,
            canvasSize: canvasSize,
            maximumLength: ComposerLogic.maxMessageLength
        )
        let result = currentText + accepted

        #expect(!accepted.isEmpty)
        #expect(accepted.count < replacement.count)
        #expect(result.count <= ComposerLogic.maxMessageLength)
        #expect(PostcardMessageLayout.fits(result, fonts: fonts, canvasSize: canvasSize))
    }
}
