import AppKit
import SwiftUI
import WebKit

/// The iPhone User Guide, hosted from the same bundled page. Topic pages push inside the guide
/// with a back button; practice state is shared between guide pages and never enters the Library.
struct MacUserGuideView: View {
    let onExit: () -> Void
    @State private var topicID: String?
    @State private var savedTerms: [String] = []

    @State private var scroll = MacGuideScroll()

    var body: some View {
        MacUserGuideWebView(topicID: topicID, savedTerms: $savedTerms, scroll: $scroll) { topicID = $0 }
            .id(topicID ?? "index")
            .ignoresSafeArea()
            .overlay { MacScrollEdgeFades(top: scroll.top, bottom: scroll.bottom) }
            .overlay(alignment: .topLeading) {
                MacBackCapsule(title: topicID == nil ? "Settings" : "User Guide") {
                    if topicID == nil { onExit() } else { topicID = nil }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AngroveTheme.Colors.canvas)
            .onChange(of: topicID) { scroll = MacGuideScroll() }
    }
}

struct MacGuideScroll: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

private struct MacUserGuideWebView: NSViewRepresentable {
    let topicID: String?
    @Binding var savedTerms: [String]
    @Binding var scroll: MacGuideScroll
    var onSelectTopic: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(UserGuideReadingHistory.key) private var visitedTopicsJSON = "[]"

    private var visitedTopics: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(visitedTopicsJSON.utf8))) ?? []
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(savedTerms: $savedTerms, scroll: $scroll, onSelectTopic: onSelectTopic)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        for name in Coordinator.messageNames {
            configuration.userContentController.add(context.coordinator, name: name)
        }
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.guideContext = \(Self.json(PageContext(topicID: topicID, savedTerms: savedTerms, visitedTopics: visitedTopics, isDark: colorScheme == .dark, palette: Self.palette(for: colorScheme))));",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: MacUserGuideCopy.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.pageScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.setAccessibilityLabel(String(localized: "User Guide"))
        context.coordinator.appearanceScript = Self.appearanceScript(for: colorScheme)
        if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "html") {
            context.coordinator.guideURL = url
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            assertionFailure("The bundled UserGuide.html resource is missing")
            webView.loadHTMLString("<p>User Guide could not be loaded.</p>", baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.savedTerms = $savedTerms
        context.coordinator.scroll = $scroll
        context.coordinator.onSelectTopic = onSelectTopic
        let script = Self.appearanceScript(for: colorScheme)
        if context.coordinator.appearanceScript != script {
            context.coordinator.appearanceScript = script
            webView.evaluateJavaScript(script)
        }
        webView.evaluateJavaScript("window.restoreGuideSavedTerms?.(\(Self.json(savedTerms)))")
        webView.evaluateJavaScript("window.restoreGuideVisitedTopics?.(\(Self.json(visitedTopics)))")
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        for name in Coordinator.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    /// The page runs edge to edge under the back capsule and fades, so it gets its own top and bottom
    /// room, and reports its scroll position for the fades.
    private static let pageScript = """
    (() => {
        const style = document.createElement('style');
        style.textContent = 'body { padding-top: 84px; padding-bottom: 48px; }';
        document.head.appendChild(style);
        const report = () => {
            const root = document.documentElement;
            const max = root.scrollHeight - window.innerHeight;
            window.webkit.messageHandlers.guideScroll.postMessage([window.scrollY, Math.max(max - window.scrollY, 0)]);
        };
        window.addEventListener('scroll', report, { passive: true });
        window.addEventListener('resize', report);
        new ResizeObserver(report).observe(document.body);
        report();
    })();
    """

    private static func appearanceScript(for scheme: ColorScheme) -> String {
        "window.applyGuideAppearance?.(\(json(palette(for: scheme))), \(scheme == .dark));"
    }

    private struct PageContext: Encodable {
        let topicID: String?
        let savedTerms: [String]
        let visitedTopics: [String]
        let isDark: Bool
        let palette: [String: String]
        let nativeScrolling = true
    }

    // All values are internal Encodable strings/bools, so JSONEncoder cannot fail.
    private static func json<T: Encodable>(_ value: T) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func palette(for scheme: ColorScheme) -> [String: String] {
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
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) ?? .currentDrawing()
        var result: [String: String] = [:]
        for (name, color) in colors {
            var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
            appearance.performAsCurrentDrawingAppearance {
                if let resolved = NSColor(color).usingColorSpace(.sRGB) {
                    rgba = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
                }
            }
            let rgb = "\(Int((rgba.0 * 255).rounded())),\(Int((rgba.1 * 255).rounded())),\(Int((rgba.2 * 255).rounded()))"
            if name.hasPrefix("guide-") { result[name + "-rgb"] = rgb }
            else { result[name] = "rgba(\(rgb),\(rgba.3))" }
        }
        return result
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageNames = ["guideCopy", "guideTopic", "guideSaved", "guideScroll"]
        var guideURL: URL?
        var appearanceScript = ""
        var savedTerms: Binding<[String]>
        var scroll: Binding<MacGuideScroll>
        var onSelectTopic: (String) -> Void

        init(savedTerms: Binding<[String]>, scroll: Binding<MacGuideScroll>, onSelectTopic: @escaping (String) -> Void) {
            self.savedTerms = savedTerms
            self.scroll = scroll
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
                  message.frameInfo.request.url?.lastPathComponent == "UserGuide.html" else { return }
            switch message.name {
            case "guideCopy":
                if let text = message.body as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            case "guideTopic":
                guard let id = message.body as? String, UserGuideTopic.topic(id: id) != nil else { return }
                UserGuideReadingHistory.markVisited(id)
                onSelectTopic(id)
            case "guideScroll":
                guard let values = message.body as? [Double], values.count == 2 else { return }
                func amount(_ distance: Double) -> CGFloat { CGFloat((min(max(distance, 0) / 48, 1) * 20).rounded() / 20) }
                let next = MacGuideScroll(top: amount(values[0]), bottom: amount(values[1]))
                if scroll.wrappedValue != next { scroll.wrappedValue = next }
            case "guideSaved":
                guard let terms = message.body as? [String] else { return }
                let valid = Array(Set(terms.filter { ["eudaimonia", "natural-philosophy"].contains($0) })).sorted()
                if savedTerms.wrappedValue.sorted() != valid { savedTerms.wrappedValue = valid }
            default: break
            }
        }
    }
}

/// The bundled guide is the website's iPhone guide. On the Mac, this swaps the passages that
/// describe iPhone-only controls for what Mac Settings and the Mac workspace actually offer, then
/// converts the remaining touch wording.
enum MacUserGuideCopy {
    enum Part: String { case intro, does = "What it does", how = "How to use it", helps = "When it helps" }

    static let overrides: [String: [Part: String]] = [
        "conversation": [
            .intro: "A conversation is where you ask Angrove a question and talk it through. Press Command-N to begin. Think of it as a patient study partner: you can ask anything, push back, and keep going.",
        ],
        "tree": [
            .intro: "Every conversation has an Insight Tree: a map of the ideas you’ve explored. Open it with the Insight Tree button at the top of a conversation, or press Command-T. It shows how your saved Insights relate to one another, so you can see the shape of a subject instead of scrolling back through a long discussion.",
        ],
        "organization": [
            .how: "Open Conversations to search, rename, pin, move to a Study Topic, or delete a conversation; Control-click a conversation in the sidebar for the same actions. Open Study Topics to create a topic, give it a short description, and add conversations to it.",
        ],
        "model-tasks": [
            .intro: "Angrove runs entirely on your Mac, so it works on one thing at a time: answering a question, defining a word, updating your tree. Anything else you ask for waits in line. Model Tasks shows that line, so you can see what Angrove is doing and change what happens next. Open it with the status button in the model controls, which reads Idle or Thinking, or press Command-M.",
        ],
        "personalization": [
            .intro: "You can make Angrove more comfortable to read and tell it what to call you. Everything is in Settings, at the bottom of the sidebar, or press Command-Comma.",
            .how: "Appearance chooses light, dark, or your Mac’s setting, and the backgrounds behind conversations and the Insight Tree. Conversations sets the response and question fonts, text size, how conversations are titled, and where Angrove opens. Personalization sets the name Angrove greets you with. Read Aloud and Notifications set listening and reminders.",
        ],
        "privacy": [
            .intro: "Everything you do in Angrove stays on your Mac. Your conversations, saved Insights, and the model that answers you are never sent to a server. In Settings, Privacy locks the app, and Your Data backs up or clears your data.",
            .does: "Your conversations and Insights are stored only on your Mac, and the model runs on it too.",
            .how: "Turn on App Lock to require Touch ID or your Mac password, and choose how soon it locks. Export saves your conversations to a file, and Import reads one back. Clear Insight Tree removes saved Insights and tree data but keeps your conversations.",
        ],
    ]

    /// Ordered so longer phrases are replaced before the words inside them.
    static let wording: [(String, String)] = [
        ("on your phone", "on your Mac"), ("your phone", "your Mac"), ("iOS version", "macOS version"),
        ("at the bottom of the menu", "at the bottom of the sidebar"), ("in the menu", "in the sidebar"),
        ("from the menu", "from the sidebar"), ("press and drag", "drag"),
        ("Tapping", "Clicking"), ("tapping", "clicking"), ("Tap", "Click"), ("tap", "click"),
    ]

    static var script: String {
        let parts = overrides.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) }
        let data = try! JSONSerialization.data(withJSONObject: ["overrides": parts, "wording": wording.map { [$0.0, $0.1] }], options: [.sortedKeys])
        return """
        (() => {
            const copy = \(String(decoding: data, as: UTF8.self));
            for (const [id, parts] of Object.entries(copy.overrides)) {
                const article = document.getElementById(id);
                if (!article) continue;
                for (const [part, text] of Object.entries(parts)) {
                    const target = part === 'intro'
                        ? article.querySelector('.guide-topic__intro')
                        : [...article.querySelectorAll('h3.guide-label')].find(h => h.textContent.trim() === part)?.nextElementSibling;
                    if (target) target.textContent = text;
                }
            }
            const words = copy.wording.map(([from, to]) => [new RegExp('\\\\b' + from + '\\\\b', 'g'), to]);
            const convert = text => words.reduce((result, [pattern, to]) => result.replace(pattern, to), text);
            // Demo windows write their hints after load, so text added later is converted too.
            const convertTree = root => {
                if (root.nodeType === Node.TEXT_NODE) {
                    if (root.parentElement?.closest('script, style')) return;
                    const text = convert(root.nodeValue);
                    if (text !== root.nodeValue) root.nodeValue = text;
                    return;
                }
                if (root.nodeType !== Node.ELEMENT_NODE || root.matches('script, style')) return;
                for (const element of [root, ...root.querySelectorAll('[aria-label]')]) {
                    const label = element.getAttribute('aria-label');
                    if (label && convert(label) !== label) element.setAttribute('aria-label', convert(label));
                }
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                for (let node = walker.nextNode(); node; node = walker.nextNode()) convertTree(node);
            };
            convertTree(document.body);
            new MutationObserver(records => records.forEach(record => {
                if (record.type === 'characterData') convertTree(record.target);
                record.addedNodes.forEach(convertTree);
            })).observe(document.body, { childList: true, characterData: true, subtree: true });
        })();
        """
    }
}
