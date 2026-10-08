import SwiftUI
import UIKit

/// A selectable reader paragraph that adds Ask and Clip to UIKit's native selection menu.
struct LibrarySelectionText: UIViewRepresentable {
    let text: AttributedString
    let onAsk: (String) -> Void
    let onClip: (String) -> Void
    let onOpenURL: (URL) -> Bool
    let textColor: Color
    let fontName: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> AskingTextView {
        let view = AskingTextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.ask = { [weak coordinator = context.coordinator] selected in
            coordinator?.onAsk(selected)
        }
        view.clip = { [weak coordinator = context.coordinator] selected in
            coordinator?.onClip(selected)
        }
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: AskingTextView, context: Context) {
        context.coordinator.onAsk = onAsk
        context.coordinator.onClip = onClip
        context.coordinator.onOpenURL = onOpenURL
        let font = UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let incoming = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let fullRange = NSRange(location: 0, length: incoming.length)
        // Keep explicit verse/link typography while supplying the reader's body font.
        incoming.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil { incoming.addAttribute(.font, value: font, range: range) }
        }
        let paragraph = NSMutableParagraphStyle()
        // Match response rows: preserve natural font metrics and add the shared gap.
        paragraph.lineSpacing = FlowLayout.rowSpacing
        incoming.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
        if !view.attributedText.isEqual(to: incoming) {
            let selection = view.selectedRange
            view.attributedText = incoming
            if NSMaxRange(selection) <= incoming.length { view.selectedRange = selection }
        }
        view.textColor = UIColor(textColor)
        // UIKit's default link attributes override the attributed citation color.
        let linkColor = UIColor.angroveLinkGreen
        view.linkTextAttributes = [.foregroundColor: linkColor]
        view.tintColor = linkColor
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AskingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onAsk: onAsk, onClip: onClip, onOpenURL: onOpenURL) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onAsk: (String) -> Void
        var onClip: (String) -> Void
        var onOpenURL: (URL) -> Bool
        init(onAsk: @escaping (String) -> Void, onClip: @escaping (String) -> Void, onOpenURL: @escaping (URL) -> Bool) {
            self.onAsk = onAsk
            self.onClip = onClip
            self.onOpenURL = onOpenURL
        }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            onOpenURL(URL)
        }
    }
}

final class AskingTextView: UITextView {
    var ask: ((String) -> Void)?
    var clip: ((String) -> Void)?

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let selected = text(in: textRange)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selected.isEmpty else { return UIMenu(children: suggestedActions) }
        let askAction = UIAction(title: "Ask", image: UIImage(systemName: "arrow.turn.down.right")) { [weak self] _ in
            self?.ask?(selected)
        }
        let clipAction = UIAction(title: "Clip", image: UIImage(systemName: "bookmark")) { [weak self] _ in
            self?.clip?(selected)
        }
        return UIMenu(children: [askAction, clipAction] + suggestedActions)
    }
}
