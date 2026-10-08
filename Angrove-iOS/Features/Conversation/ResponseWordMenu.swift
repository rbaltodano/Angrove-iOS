import SwiftUI
import UIKit

/// A reader's request to define a plain word of a response.
struct ResponseWordDefinitionRequest {
    let token: String
    let location: DefinedTermMarkup.Location
}

extension EnvironmentValues {
    /// Defines a word of the enclosing response. Nil where a response is only displayed (for
    /// example the User Guide), which leaves the word menu with Copy alone.
    @Entry var defineResponseWord: ((ResponseWordDefinitionRequest) -> Void)? = nil
}

extension View {
    /// Long-pressing a response word opens the edit menu on it with Copy and, where the
    /// response can be annotated, Define. It replaces the system's per-word text selection
    /// menu, which cannot take extra actions.
    func responseWordMenu(
        token: String,
        onReadFromHere: (() -> Void)? = nil,
        location: @escaping () -> DefinedTermMarkup.Location
    ) -> some View {
        modifier(ResponseWordMenuModifier(token: token, onReadFromHere: onReadFromHere, location: location))
    }
}

private struct ResponseWordMenuModifier: ViewModifier {
    let token: String
    let onReadFromHere: (() -> Void)?
    let location: () -> DefinedTermMarkup.Location

    @Environment(\.defineResponseWord) private var defineResponseWord
    @State private var isMenuPresented = false

    func body(content: Content) -> some View {
        content
            .textSelection(.disabled)
            .background {
                if isMenuPresented {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AngroveTheme.Colors.wordHighlight)
                        .padding(.horizontal, -3)
                        .padding(.vertical, -1)
                        .background(
                            WordEditMenuPresenter(
                                copyText: token.filter { $0 != "*" },
                                onDefine: defineAction,
                                onReadFromHere: onReadFromHere,
                                onDismiss: { isMenuPresented = false }
                            )
                        )
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.4) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isMenuPresented = true
            }
    }

    private var defineAction: (() -> Void)? {
        guard let defineResponseWord, DefinedTermMarkup.term(in: token) != nil else { return nil }
        return {
            defineResponseWord(ResponseWordDefinitionRequest(token: token, location: location()))
        }
    }
}

/// Sits behind the pressed word and presents the system edit menu from the word's own frame.
private struct WordEditMenuPresenter: UIViewRepresentable {
    let copyText: String
    let onDefine: (() -> Void)?
    let onReadFromHere: (() -> Void)?
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> WordEditMenuView {
        let view = WordEditMenuView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: WordEditMenuView, context: Context) {
        view.copyText = copyText
        view.onDefine = onDefine
        view.onReadFromHere = onReadFromHere
        view.onDismiss = onDismiss
    }
}

private final class WordEditMenuView: UIView, UIEditMenuInteractionDelegate {
    var copyText = ""
    var onDefine: (() -> Void)?
    var onReadFromHere: (() -> Void)?
    var onDismiss: () -> Void = {}

    private lazy var menuInteraction = UIEditMenuInteraction(delegate: self)
    private var hasPresented = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasPresented else { return }
        hasPresented = true
        addInteraction(menuInteraction)
        // Present after layout so the menu points at the word's final frame.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            let configuration = UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            )
            // Above the word when there is room, so the menu doesn't cover the lines below it.
            configuration.preferredArrowDirection = .down
            self.menuInteraction.presentEditMenu(with: configuration)
        }
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        var actions = [
            UIAction(title: String(localized: "Copy")) { [copyText] _ in
                UIPasteboard.general.string = copyText
            }
        ]
        if let onDefine {
            actions.append(UIAction(title: String(localized: "Define")) { _ in onDefine() })
        }
        if let onReadFromHere {
            actions.append(UIAction(title: String(localized: "Read from here")) { _ in onReadFromHere() })
        }
        return UIMenu(children: actions)
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        bounds
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        animator.addCompletion { [weak self] in self?.onDismiss() }
    }
}
