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
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
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
        textView.isScrollEnabled = isEditable
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
    }
}

final class StampWrappingTextView: UITextView {
    private var exclusionLayoutSize: CGSize = .zero

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

        // Matches the printed stamp box in the PostcardBack artwork.
        let stampBox = CGRect(
            x: bounds.width * 0.706,
            y: bounds.height * 0.064,
            width: bounds.width * 0.183,
            height: bounds.height * 0.119
        )
        let stampPadding = bounds.width * 0.03
        let paddedStampBox = stampBox.insetBy(dx: -stampPadding, dy: -stampPadding)
        let textContainerStampBox = paddedStampBox.offsetBy(
            dx: -textContainerInset.left,
            dy: -textContainerInset.top
        )

        textContainer.exclusionPaths = [UIBezierPath(rect: textContainerStampBox)]
    }
}
