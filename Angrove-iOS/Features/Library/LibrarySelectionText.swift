import SwiftUI
import UIKit

/// A selectable reader paragraph that adds Ask to UIKit's native selection menu.
struct LibrarySelectionText: UIViewRepresentable {
    let text: AttributedString
    let onAsk: (String) -> Void
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
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: AskingTextView, context: Context) {
        context.coordinator.onAsk = onAsk
        context.coordinator.onOpenURL = onOpenURL
        let incoming = NSAttributedString(text)
        if !view.attributedText.isEqual(to: incoming) {
            view.attributedText = incoming
            view.font = UIFont(name: fontName, size: fontSize)
            view.typingAttributes = [
                .font: view.font as Any,
                .foregroundColor: UIColor.label
            ]
        }
        view.textColor = UIColor(textColor)
        view.font = UIFont(name: fontName, size: fontSize)
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AskingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onAsk: onAsk, onOpenURL: onOpenURL) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onAsk: (String) -> Void
        var onOpenURL: (URL) -> Bool
        init(onAsk: @escaping (String) -> Void, onOpenURL: @escaping (URL) -> Bool) {
            self.onAsk = onAsk
            self.onOpenURL = onOpenURL
        }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            onOpenURL(URL)
        }
    }
}

final class AskingTextView: UITextView {
    var ask: ((String) -> Void)?

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let selected = text(in: textRange)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selected.isEmpty else { return UIMenu(children: suggestedActions) }
        let askAction = UIAction(title: "Ask", image: UIImage(systemName: "arrow.turn.down.right")) { [weak self] _ in
            self?.ask?(selected)
        }
        return UIMenu(children: [askAction] + suggestedActions)
    }
}
