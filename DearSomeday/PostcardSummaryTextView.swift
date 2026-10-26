import SwiftUI
import UIKit

/// Read-only summary text that fills the column beside the postcard preview,
/// then continues at full width below the preview.
struct PostcardSummaryTextView: UIViewRepresentable {
    let title: String
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
        paragraphStyle.lineBreakMode = .byCharWrapping

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            let titleFont = UIFont(name: "BodoniModa9pt-Regular", size: 17)
                ?? UIFont.preferredFont(forTextStyle: .headline)
            result.append(NSAttributedString(
                string: trimmedTitle,
                attributes: [
                    .font: titleFont,
                    .foregroundColor: UIColor(Tokens.Color.chromeText),
                    .paragraphStyle: paragraphStyle
                ]
            ))
            result.append(NSAttributedString(string: "\n\n"))
        }

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
    private static let columnSpacing: CGFloat = 16
    private static let bottomSpacing: CGFloat = 12

    private let sideTextView = PostcardSummaryFlowView.makeTextView()
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
        addSubview(sideTextView)
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

        let previewWidth = max((width - Self.columnSpacing) / 2, 0)
        let previewHeight = previewWidth / PostcardCanvasMetrics.aspectRatio
        let sideSize = CGSize(width: previewWidth, height: previewHeight)
        let splitLocation = fittingCharacterCount(in: attributedText, size: sideSize)
        let sideRange = NSRange(location: 0, length: splitLocation)
        let bottomRange = NSRange(
            location: splitLocation,
            length: max(attributedText.length - splitLocation, 0)
        )

        sideTextView.attributedText = attributedText.attributedSubstring(from: sideRange)
        sideTextView.frame = CGRect(
            x: previewWidth + Self.columnSpacing,
            y: 0,
            width: previewWidth,
            height: previewHeight
        )

        guard bottomRange.length > 0 else {
            bottomTextView.attributedText = NSAttributedString()
            bottomTextView.frame = .zero
            return previewHeight
        }

        let remainingText = attributedText.attributedSubstring(from: bottomRange)
        let bottomHeight = measuredHeight(of: remainingText, width: width)
        bottomTextView.attributedText = remainingText
        bottomTextView.frame = CGRect(
            x: 0,
            y: previewHeight + Self.bottomSpacing,
            width: width,
            height: bottomHeight
        )
        return previewHeight + Self.bottomSpacing + bottomHeight
    }

    private func fittingCharacterCount(in text: NSAttributedString, size: CGSize) -> Int {
        guard text.length > 0, size.width > 0, size.height > 0 else { return 0 }

        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let container = makeTextContainer(size: size)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let glyphRange = layoutManager.glyphRange(for: container)
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        return min(NSMaxRange(characterRange), text.length)
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
        container.lineBreakMode = .byCharWrapping
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
        textView.textContainer.lineBreakMode = .byCharWrapping
        return textView
    }
}
