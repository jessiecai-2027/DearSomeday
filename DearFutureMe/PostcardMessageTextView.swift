import SwiftUI
import UIKit

/// A postcard message field whose lines flow around the printed stamp box.
struct PostcardMessageTextView: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    let textColor: UIColor
    let isEditable: Bool

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
        textView.adjustsFontForContentSizeCategory = true
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

        textView.font = font
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
            if (proposedText as NSString).length < (textView.text as NSString).length {
                return true
            }
            if textView.canFit(proposedText) {
                return true
            }

            let replacementCharacters = Array(replacement)
            guard replacementCharacters.count > 1 else { return false }

            var lowerBound = 0
            var upperBound = replacementCharacters.count
            while lowerBound < upperBound {
                let candidateLength = (lowerBound + upperBound + 1) / 2
                let candidateReplacement = String(replacementCharacters.prefix(candidateLength))
                let candidateText = textView.text.replacingCharacters(
                    in: swiftRange,
                    with: candidateReplacement
                )

                if textView.canFit(candidateText) {
                    lowerBound = candidateLength
                } else {
                    upperBound = candidateLength - 1
                }
            }

            guard lowerBound > 0 else { return false }

            let acceptedReplacement = String(replacementCharacters.prefix(lowerBound))
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
            return false
        }
    }
}

final class StampWrappingTextView: UITextView {
    private var exclusionLayoutSize: CGSize = .zero

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != exclusionLayoutSize else { return }
        exclusionLayoutSize = bounds.size

        let edgePadding = bounds.width * 0.07
        textContainerInset = UIEdgeInsets(
            top: edgePadding,
            left: edgePadding,
            bottom: edgePadding,
            right: edgePadding
        )
        textContainer.size = CGSize(
            width: max(bounds.width - textContainerInset.left - textContainerInset.right, 0),
            height: max(bounds.height - textContainerInset.top - textContainerInset.bottom, 0)
        )

        // Matches the printed stamp box in the PostcardBack artwork.
        let stampBox = CGRect(
            x: bounds.width * 0.706,
            y: bounds.height * 0.064,
            width: bounds.width * 0.183,
            height: bounds.height * 0.119
        )
        let stampPadding = bounds.width * 0.03
        let paddedStampBox = stampBox.insetBy(dx: -stampPadding, dy: -stampPadding)
        let textContainerStampBox = CGRect(
            x: paddedStampBox.minX - textContainerInset.left,
            y: paddedStampBox.minY - textContainerInset.top,
            width: bounds.width,
            height: paddedStampBox.height
        )

        textContainer.exclusionPaths = [UIBezierPath(rect: textContainerStampBox)]
    }

    func canFit(_ proposedText: String) -> Bool {
        layoutIfNeeded()
        guard let font else { return true }

        let availableSize = CGSize(
            width: max(bounds.width - textContainerInset.left - textContainerInset.right, 0),
            height: max(bounds.height - textContainerInset.top - textContainerInset.bottom, 0)
        )
        guard availableSize.width > 0, availableSize.height > 0 else { return false }

        let storage = NSTextStorage(string: proposedText, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let measuringContainer = NSTextContainer(size: availableSize)
        measuringContainer.lineFragmentPadding = textContainer.lineFragmentPadding
        measuringContainer.lineBreakMode = textContainer.lineBreakMode
        measuringContainer.exclusionPaths = textContainer.exclusionPaths
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(measuringContainer)
        layoutManager.ensureLayout(for: measuringContainer)

        let glyphRange = layoutManager.glyphRange(for: measuringContainer)
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        return NSMaxRange(characterRange) >= (proposedText as NSString).length
    }
}
