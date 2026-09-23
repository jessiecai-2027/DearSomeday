import SwiftUI
import UIKit

/// TextKit measurements shared by the composer and the rendered postcard back.
enum PostcardMessageLayout {
    static func configure(_ container: NSTextContainer, for canvasSize: CGSize) {
        let edgePadding = canvasSize.width * 0.07
        container.size = CGSize(
            width: max(canvasSize.width - edgePadding * 2, 0),
            height: max(canvasSize.height - edgePadding * 2, 0)
        )
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byCharWrapping

        let stampBox = PostcardBackLayout.stampFrame(in: canvasSize)
        let stampPadding = canvasSize.width * 0.03
        let paddedStampBox = stampBox.insetBy(dx: -stampPadding, dy: -stampPadding)
        let containerStampBox = CGRect(
            x: paddedStampBox.minX - edgePadding,
            y: paddedStampBox.minY - edgePadding,
            width: canvasSize.width,
            height: paddedStampBox.height
        )
        container.exclusionPaths = [UIBezierPath(rect: containerStampBox)]
    }

    static func fits(_ text: String, font: UIFont, canvasSize: CGSize) -> Bool {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return false }
        guard !text.isEmpty else { return true }

        // TextKit does not materialize the final empty line when a string ends
        // in one or more newlines. A sentinel on that already-empty line makes
        // the editor's trailing caret line participate in measurement.
        let measuredText = text.hasSuffix("\n") ? text + "M" : text
        let storage = NSTextStorage(string: measuredText, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer()
        configure(container, for: canvasSize)
        let availableHeight = container.size.height
        // Lay out the complete message, then compare its real height with the
        // postcard. A finite-height container can report newline glyphs as
        // consumed while collapsing their overflowing empty fragments.
        container.size.height = .greatestFiniteMagnitude
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let glyphRange = layoutManager.glyphRange(for: container)
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        guard NSMaxRange(characterRange) >= (measuredText as NSString).length else {
            return false
        }

        // Newline glyphs may all be consumed even when their line fragments
        // extend beyond the container. Include both rendered text and the
        // trailing caret line so repeated returns cannot escape the limit.
        let renderedBottom = max(
            layoutManager.usedRect(for: container).maxY,
            layoutManager.extraLineFragmentUsedRect.maxY
        )
        return renderedBottom <= availableHeight + 0.5
    }

    static func fits(_ text: String, fonts: [UIFont], canvasSize: CGSize) -> Bool {
        fonts.allSatisfy { fits(text, font: $0, canvasSize: canvasSize) }
    }

    static func longestFittingReplacement(
        in currentText: String,
        replacing range: Range<String.Index>,
        with replacement: String,
        fonts: [UIFont],
        canvasSize: CGSize,
        maximumLength: Int
    ) -> String {
        let replacementCharacters = Array(replacement)
        var lowerBound = 0
        var upperBound = replacementCharacters.count

        while lowerBound < upperBound {
            let candidateLength = (lowerBound + upperBound + 1) / 2
            let candidateReplacement = String(replacementCharacters.prefix(candidateLength))
            let candidateText = currentText.replacingCharacters(
                in: range,
                with: candidateReplacement
            )
            if candidateText.count <= maximumLength,
               fits(candidateText, fonts: fonts, canvasSize: canvasSize) {
                lowerBound = candidateLength
            } else {
                upperBound = candidateLength - 1
            }
        }
        return String(replacementCharacters.prefix(lowerBound))
    }

    static func largestFittingPointSize(
        for text: String,
        font: PostcardBackFont,
        canvasSize: CGSize,
        minimum: CGFloat = PostcardBackFont.minimumLockedPointSize,
        maximum: CGFloat = PostcardBackFont.normalPointSize
    ) -> CGFloat? {
        if fits(text, font: font.uiFont(pointSize: maximum), canvasSize: canvasSize) {
            return maximum
        }
        guard fits(text, font: font.uiFont(pointSize: minimum), canvasSize: canvasSize) else {
            return nil
        }

        var fittingSize = minimum
        var overflowingSize = maximum
        for _ in 0..<12 {
            let candidate = (fittingSize + overflowingSize) / 2
            if fits(text, font: font.uiFont(pointSize: candidate), canvasSize: canvasSize) {
                fittingSize = candidate
            } else {
                overflowingSize = candidate
            }
        }
        return fittingSize
    }
}

/// A postcard message field whose lines flow around the printed stamp box.
struct PostcardMessageTextView: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    let textColor: UIColor
    let isEditable: Bool
    var validationFonts: [UIFont] = []
    var maximumLength = ComposerLogic.maxMessageLength
    var adaptiveMinimumPointSize: CGFloat? = PostcardBackFont.minimumLegacyPointSize
    var onCapacityChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> StampWrappingTextView {
        let textView = StampWrappingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.clipsToBounds = true
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.heightTracksTextView = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.adjustsFontForContentSizeCategory = false
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.alwaysBounceHorizontal = false
        return textView
    }

    func updateUIView(_ textView: StampWrappingTextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            textView.text = text
        }

        textView.setFont(font, fitting: text, adaptiveMinimumPointSize: adaptiveMinimumPointSize)
        textView.textColor = textColor
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = isEditable
        textView.setNeedsLayout()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PostcardMessageTextView

        init(parent: PostcardMessageTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard
                let textView = textView as? StampWrappingTextView,
                let swiftRange = Range(range, in: textView.text)
            else { return false }

            let proposedText = textView.text.replacingCharacters(in: swiftRange, with: replacement)
            if replacement.isEmpty {
                parent.onCapacityChange?(false)
                return true
            }

            let proposedFits = accepts(proposedText, in: textView)
            if proposedFits {
                parent.onCapacityChange?(false)
                return true
            }

            guard replacement.count > 1 else {
                parent.onCapacityChange?(isVisualOverflow(proposedText, in: textView))
                return false
            }

            let validationFonts = textView.resolvedValidationFonts(parent.validationFonts)
            let acceptedReplacement = PostcardMessageLayout.longestFittingReplacement(
                in: textView.text,
                replacing: swiftRange,
                with: replacement,
                fonts: validationFonts,
                canvasSize: textView.bounds.size,
                maximumLength: parent.maximumLength
            )
            guard !acceptedReplacement.isEmpty else {
                parent.onCapacityChange?(isVisualOverflow(proposedText, in: textView))
                return false
            }

            let acceptedText = textView.text.replacingCharacters(
                in: swiftRange,
                with: acceptedReplacement
            )
            textView.text = acceptedText
            textView.selectedRange = NSRange(
                location: range.location + (acceptedReplacement as NSString).length,
                length: 0
            )
            parent.text = acceptedText
            parent.onCapacityChange?(isVisualOverflow(proposedText, in: textView))
            return false
        }

        private func accepts(_ candidate: String, in textView: StampWrappingTextView) -> Bool {
            candidate.count <= parent.maximumLength
                && textView.canFit(candidate, using: parent.validationFonts)
        }

        private func isVisualOverflow(_ candidate: String, in textView: StampWrappingTextView) -> Bool {
            candidate.count <= parent.maximumLength
                && !textView.canFit(candidate, using: parent.validationFonts)
        }
    }
}

final class StampWrappingTextView: UITextView {
    private var configuredCanvasSize: CGSize = .zero
    private var requestedFont: UIFont?
    private var textToFit = ""
    private var adaptiveMinimumPointSize: CGFloat?

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        if bounds.size != configuredCanvasSize {
            configuredCanvasSize = bounds.size
            let edgePadding = bounds.width * 0.07
            textContainerInset = UIEdgeInsets(
                top: edgePadding,
                left: edgePadding,
                bottom: edgePadding,
                right: edgePadding
            )
            PostcardMessageLayout.configure(textContainer, for: bounds.size)
        }
        applyRequestedFont()
    }

    func setFont(
        _ font: UIFont,
        fitting text: String,
        adaptiveMinimumPointSize: CGFloat?
    ) {
        requestedFont = font
        textToFit = text
        self.adaptiveMinimumPointSize = adaptiveMinimumPointSize
        applyRequestedFont()
    }

    func canFit(_ proposedText: String, using validationFonts: [UIFont]) -> Bool {
        layoutIfNeeded()
        return PostcardMessageLayout.fits(
            proposedText,
            fonts: resolvedValidationFonts(validationFonts),
            canvasSize: bounds.size
        )
    }

    func resolvedValidationFonts(_ validationFonts: [UIFont]) -> [UIFont] {
        validationFonts.isEmpty ? [font].compactMap { $0 } : validationFonts
    }

    private func applyRequestedFont() {
        guard let requestedFont else { return }
        guard let adaptiveMinimumPointSize else {
            if font != requestedFont { font = requestedFont }
            return
        }
        guard bounds.width > 0, bounds.height > 0 else {
            font = requestedFont
            return
        }

        let maximum = requestedFont.pointSize
        let minimum = min(adaptiveMinimumPointSize, maximum)
        let resolvedSize: CGFloat
        if PostcardMessageLayout.fits(textToFit, font: requestedFont, canvasSize: bounds.size) {
            resolvedSize = maximum
        } else {
            var fittingSize = minimum
            var overflowingSize = maximum
            for _ in 0..<12 {
                let candidate = (fittingSize + overflowingSize) / 2
                if PostcardMessageLayout.fits(
                    textToFit,
                    font: requestedFont.withSize(candidate),
                    canvasSize: bounds.size
                ) {
                    fittingSize = candidate
                } else {
                    overflowingSize = candidate
                }
            }
            resolvedSize = fittingSize
        }

        let resolvedFont = requestedFont.withSize(resolvedSize)
        if font?.fontName != resolvedFont.fontName
            || abs((font?.pointSize ?? 0) - resolvedFont.pointSize) > 0.01 {
            font = resolvedFont
        }
    }
}
