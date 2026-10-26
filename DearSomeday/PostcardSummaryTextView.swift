import SwiftUI
import UIKit

/// Full-width message below the photo and stamp previews.
struct PostcardSummaryTextView: UIViewRepresentable {
    let message: String
    let messageFont: UIFont
    let messageColor: UIColor

    func makeUIView(context: Context) -> PostcardSummaryFlowView {
        PostcardSummaryFlowView()
    }

    func updateUIView(_ view: PostcardSummaryFlowView, context: Context) {
        view.attributedText = attributedText
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView view: PostcardSummaryFlowView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        view.attributedText = attributedText
        return view.fittingSize(for: width)
    }

    private var attributedText: NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.hyphenationFactor = 0

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        result.append(NSAttributedString(
            string: trimmedMessage.isEmpty ? "No message" : message,
            attributes: [
                .font: messageFont,
                .foregroundColor: trimmedMessage.isEmpty
                    ? UIColor(Tokens.Color.chromeText).withAlphaComponent(0.6)
                    : messageColor,
                .paragraphStyle: paragraphStyle
            ]
        ))
        return result
    }
}

final class PostcardSummaryFlowView: UIView {
    private let bottomTextView = PostcardSummaryFlowView.makeTextView()

    var attributedText = NSAttributedString() {
        didSet {
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(bottomTextView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = layoutText(for: bounds.width)
    }

    func fittingSize(for width: CGFloat) -> CGSize {
        CGSize(width: width, height: layoutText(for: width))
    }

    private func layoutText(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }

        let bottomHeight = measuredHeight(of: attributedText, width: width)
        bottomTextView.attributedText = attributedText
        bottomTextView.frame = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: bottomHeight
        )
        return bottomHeight
    }

    private func measuredHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0, width > 0 else { return 0 }

        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let container = makeTextContainer(size: CGSize(width: width, height: 10_000))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).maxY)
    }

    private func makeTextContainer(size: CGSize) -> NSTextContainer {
        let container = NSTextContainer(size: size)
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        return container
    }

    private static func makeTextView() -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.clipsToBounds = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        return textView
    }
}
