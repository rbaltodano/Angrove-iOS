import SwiftUI
import WebKit

/// Website artwork and examples inside the app's native guide navigation.
/// Practice state is shared only between guide pages; it never enters the Insight Library.
struct UserGuideWebsiteView: UIViewRepresentable {
    let topicID: String?
    @Binding var savedTerms: [String]
    var onSelectTopic: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(UserGuideReadingHistory.key) private var visitedTopicsJSON = "[]"

    private var visitedTopics: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(visitedTopicsJSON.utf8))) ?? []
    }

    init(topicID: String? = nil, savedTerms: Binding<[String]>, onSelectTopic: @escaping (String) -> Void = { _ in }) {
        self.topicID = topicID
        self._savedTerms = savedTerms
        self.onSelectTopic = onSelectTopic
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(savedTerms: $savedTerms, onSelectTopic: onSelectTopic)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        for name in Coordinator.messageNames {
            configuration.userContentController.add(context.coordinator, name: name)
        }
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.bootstrapScript(topicID: topicID, savedTerms: savedTerms, colorScheme: colorScheme, visitedTopics: visitedTopics),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        // The page fills the screen edge to edge; safe-area insets keep its text clear of the bars.
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        // No system blur bars at the edges; the page scrolls cleanly under the status bar.
        webView.scrollView.topEdgeEffect.isHidden = true
        webView.scrollView.bottomEdgeEffect.isHidden = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        webView.accessibilityLabel = String(localized: "User Guide")
        applyAppearance(to: webView, coordinator: context.coordinator)
        if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "html") {
            context.coordinator.guideURL = url
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            assertionFailure("The bundled UserGuide.html resource is missing")
            webView.loadHTMLString("<p>User Guide could not be loaded.</p>", baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.savedTerms = $savedTerms
        context.coordinator.onSelectTopic = onSelectTopic
        applyAppearance(to: webView, coordinator: context.coordinator)
        webView.evaluateJavaScript("window.restoreGuideSavedTerms?.(\(Self.json(savedTerms)))")
        webView.evaluateJavaScript("window.restoreGuideVisitedTopics?.(\(Self.json(visitedTopics)))")
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        for name in Coordinator.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    private func applyAppearance(to webView: WKWebView, coordinator: Coordinator) {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let background = UIColor(AngroveTheme.Colors.canvas).resolvedColor(with: traits)
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        let script = Self.appearanceScript(for: colorScheme)
        guard coordinator.appearanceScript != script else { return }
        coordinator.appearanceScript = script
        webView.evaluateJavaScript(script)
    }

    static func bootstrapScript(topicID: String?, savedTerms: [String], colorScheme: ColorScheme, visitedTopics: [String] = []) -> String {
        let initial = PageContext(topicID: topicID, savedTerms: savedTerms,
                                  visitedTopics: visitedTopics, isDark: colorScheme == .dark, palette: palette(for: colorScheme))
        return "window.guideContext = \(json(initial));"
    }

    static func appearanceScript(for scheme: ColorScheme) -> String {
        "window.applyGuideAppearance?.(\(json(palette(for: scheme))), \(scheme == .dark));"
    }

    private struct PageContext: Encodable {
        let topicID: String?
        let savedTerms: [String]
        let visitedTopics: [String]
        let isDark: Bool
        let palette: [String: String]
    }

    // All values are internal Encodable strings/bools, so JSONEncoder cannot fail.
    private static func json<T: Encodable>(_ value: T) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    static func palette(for scheme: ColorScheme) -> [String: String] {
        let colors: [(String, Color)] = [
            ("canvas", AngroveTheme.Colors.canvas),
            ("canvas-secondary", AngroveTheme.Colors.canvasSecondary),
            ("app-canvas", AngroveTheme.Colors.canvas),
            ("app-surface", AngroveTheme.Colors.canvasSecondary),
            ("heading", AngroveTheme.Colors.headingText),
            ("paragraph", AngroveTheme.Colors.paragraphText),
            ("paragraph-dim", AngroveTheme.Colors.placeholderText),
            ("brown", AngroveTheme.Colors.primaryReadable),
            ("light-green", AngroveTheme.Colors.lightGreen),
            ("unread-dot", AngroveTheme.Colors.unreadDot),
            ("border", AngroveTheme.Colors.border),
            ("guide-ink", AngroveTheme.Colors.primaryReadable),
            ("guide-green", AngroveTheme.Colors.lightGreen),
            ("guide-border", AngroveTheme.Colors.primaryReadable),
            ("guide-canvas", AngroveTheme.Colors.canvas),
            ("guide-cream", AngroveTheme.Colors.canvasSecondary)
        ]
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        var result: [String: String] = [:]
        for (name, color) in colors {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let rgb = "\(Int((red * 255).rounded())),\(Int((green * 255).rounded())),\(Int((blue * 255).rounded()))"
            if name.hasPrefix("guide-") { result[name + "-rgb"] = rgb }
            else { result[name] = "rgba(\(rgb),\(alpha))" }
        }
        return result
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageNames = ["guideCopy", "guideTopic", "guideSaved"]
        var guideURL: URL?
        var appearanceScript = ""
        var savedTerms: Binding<[String]>
        var onSelectTopic: (String) -> Void

        init(savedTerms: Binding<[String]>, onSelectTopic: @escaping (String) -> Void) {
            self.savedTerms = savedTerms
            self.onSelectTopic = onSelectTopic
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(appearanceScript)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            let isGuide = url?.isFileURL == true && url?.path == guideURL?.path
            decisionHandler(isGuide || url?.absoluteString == "about:blank" ? .allow : .cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.path == guideURL?.path else { return }
            switch message.name {
            case "guideCopy":
                if let text = message.body as? String { UIPasteboard.general.string = text }
            case "guideTopic":
                guard let id = message.body as? String, UserGuideTopic.topic(id: id) != nil else { return }
                UserGuideReadingHistory.markVisited(id)
                SettingsHaptics.playSelection()
                onSelectTopic(id)
            case "guideSaved":
                guard let terms = message.body as? [String] else { return }
                let valid = Array(Set(terms.filter { ["eudaimonia", "natural-philosophy"].contains($0) })).sorted()
                if savedTerms.wrappedValue.sorted() != valid { savedTerms.wrappedValue = valid }
            default: break
            }
        }
    }
}
