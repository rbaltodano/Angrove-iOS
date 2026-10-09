import SwiftUI
import Testing
import WebKit
@testable import Angrove_iOS

@Suite(.serialized)
@MainActor
struct UserGuideBundledPageTests {
    @Test
    func indexOpensNativeTopicPagesWithoutAnchors() async throws {
        let state = PracticeState()
        let index = try await page(topicID: nil, scheme: .light, state: state)
        #expect(try await index.evaluateJavaScript("document.querySelectorAll('.guide-topic').length") as? Int == 0)
        #expect(try await index.evaluateJavaScript("document.querySelectorAll('.guide-list button').length") as? Int == 11)
        #expect(try await index.evaluateJavaScript("document.querySelectorAll('a[href^=\"#\"]').length") as? Int == 0)
        _ = try await index.evaluateJavaScript("document.querySelector('[data-guide-topic=\"tree\"]').click()")
        try await waitUntil({ state.selected == "tree" })
        #expect(try await index.evaluateJavaScript("location.hash") as? String == "")
        let topic = try await page(topicID: state.selected, scheme: .light, state: state)
        #expect(try await topic.evaluateJavaScript("document.querySelectorAll('.guide-topic').length") as? Int == 1)
        #expect(try await topic.evaluateJavaScript("document.querySelector('.guide-topic').id") as? String == "tree")
        #expect(try await topic.evaluateJavaScript("document.querySelector('.page-hero') === null && document.querySelector('.guide__toc') === null") as? Bool == true)
        _ = try await topic.evaluateJavaScript("document.querySelector('.guide-tech__toggle').click()")
        #expect(try await topic.evaluateJavaScript("document.querySelector('#tech-tree').classList.contains('is-open')") as? Bool == true)
        try await expectNoErrors(in: index)
        try await expectNoErrors(in: topic)
    }

    @Test
    func websiteTokensFontsAndHeadlineRevealSurviveBundling() async throws {
        let index = try await page(topicID: nil, scheme: .light, state: PracticeState())
        // Stripping the Google Fonts @import once swallowed the whole :root block.
        let ease = try await index.evaluateJavaScript("getComputedStyle(document.documentElement).getPropertyValue('--ease-menu').trim()") as? String
        #expect(ease == "cubic-bezier(0.55, 0, 0.17, 1)")
        let font = try await index.evaluateJavaScript("getComputedStyle(document.body).fontFamily") as? String
        #expect(font?.hasPrefix("Figtree") == true)
        #expect(try await index.evaluateJavaScript("document.querySelector('h1.display').classList.contains('reveal') && document.querySelectorAll('h1.display .rw').length > 0") as? Bool == true)
        try await expectNoErrors(in: index)
    }

    @Test
    func demosAndTechnicalDetailsFollowBothPalettes() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for id in ["definitions", "tree", "study", "midpoint", "model-tasks", "library"] {
                let webView = try await page(topicID: id, scheme: scheme, state: PracticeState())
                let palette = UserGuideWebsiteView.palette(for: scheme)
                let actual = try await webView.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
                #expect(actual?.replacingOccurrences(of: " ", with: "") == palette["canvas"]?.replacingOccurrences(of: "rgba", with: "rgb").replacingOccurrences(of: ",1.0)", with: ")"))
                #expect(try await webView.evaluateJavaScript("document.documentElement.style.colorScheme") as? String == (scheme == .dark ? "dark" : "light"))
                let ink = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement).getPropertyValue('--guide-ink-rgb').trim()") as? String
                #expect(ink == palette["guide-ink-rgb"])
                if id == "definitions" {
                    let surface = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('.window')).backgroundColor") as? String
                    #expect(surface == actual)
                }
                for width in [320, 393, 768] {
                    webView.frame.size.width = CGFloat(width)
                    webView.layoutIfNeeded()
                    // Slower machines relayout later; allow up to a second before judging overflow.
                    var fits = false
                    for _ in 0..<20 where !fits {
                        try await Task.sleep(for: .milliseconds(50))
                        fits = try await webView.evaluateJavaScript("document.documentElement.scrollWidth <= window.innerWidth") as? Bool == true
                    }
                    #expect(fits, "Topic \(id) overflows at \(width) points")
                }
                // Live appearance changes must preserve the open topic and its state.
                let other: ColorScheme = scheme == .dark ? .light : .dark
                _ = try await webView.evaluateJavaScript(UserGuideWebsiteView.appearanceScript(for: other))
                #expect(try await webView.evaluateJavaScript("document.documentElement.style.colorScheme") as? String == (other == .dark ? "dark" : "light"))
                #expect(try await webView.evaluateJavaScript("document.querySelector('.guide-topic').id") as? String == id)
                try await expectNoErrors(in: webView)
                webView.stopLoading()
            }
        }
    }

    @Test
    func practiceBookmarksTravelBetweenPagesAndTasksStillWork() async throws {
        let state = PracticeState()
        let definitions = try await page(topicID: "definitions", scheme: .dark, state: state)
        _ = try await definitions.evaluateJavaScript("document.querySelector('[data-term=\"eudaimonia\"]').click()")
        try await waitUntil("document.querySelector('[data-card-title]').textContent === 'Eudaimonia'", in: definitions)
        _ = try await definitions.evaluateJavaScript("document.querySelector('[data-card-save]').click()")
        try await waitUntil({ state.saved == ["eudaimonia"] })
        let tree = try await page(topicID: "tree", scheme: .dark, state: state)
        #expect(try await tree.evaluateJavaScript("Array.from(document.querySelectorAll('.it-chip')).some(el => el.textContent.includes('Eudaimonia'))") as? Bool == true)
        let reopened = try await page(topicID: "definitions", scheme: .light, state: state)
        _ = try await reopened.evaluateJavaScript("document.querySelector('[data-term=\"eudaimonia\"]').click()")
        #expect(try await reopened.evaluateJavaScript("document.querySelector('[data-card-save]').getAttribute('aria-pressed')") as? String == "true")
        let tasks = try await page(topicID: "model-tasks", scheme: .dark, state: state)
        _ = try await tasks.evaluateJavaScript("document.querySelector('[data-practice=\"question\"]').click(); document.querySelector('[data-practice=\"define\"]').click()")
        #expect(try await tasks.evaluateJavaScript("document.querySelectorAll('[data-mt-rows] [data-phase=\"upcoming\"]').length") as? Int == 1)
        _ = try await tasks.evaluateJavaScript("document.querySelector('[aria-label=\"Remove queued model task\"]').click(); document.querySelector('[aria-label=\"Stop current model task\"]').click()")
        #expect(try await tasks.evaluateJavaScript("document.querySelector('[data-mt-count]').hidden") as? Bool == true)
        for webView in [definitions, tree, reopened, tasks] { try await expectNoErrors(in: webView) }
    }

    private final class PracticeState {
        var saved: [String] = []
        var selected: String?
    }

    private func page(topicID: String?, scheme: ColorScheme, state: PracticeState) async throws -> WKWebView {
        let url = try #require(Bundle.main.url(forResource: "UserGuide", withExtension: "html"))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let coordinator = UserGuideWebsiteView.Coordinator(
            savedTerms: Binding(get: { state.saved }, set: { state.saved = $0 }),
            onSelectTopic: { state.selected = $0 }
        )
        coordinator.guideURL = url
        coordinator.appearanceScript = UserGuideWebsiteView.appearanceScript(for: scheme)
        for name in UserGuideWebsiteView.Coordinator.messageNames { config.userContentController.add(coordinator, name: name) }
        config.userContentController.addUserScript(WKUserScript(
            source: "window.guideErrors = []; window.addEventListener('error', e => window.guideErrors.push(e.message));" + UserGuideWebsiteView.bootstrapScript(topicID: topicID, savedTerms: state.saved, colorScheme: scheme),
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 393, height: 800), configuration: config)
        webView.navigationDelegate = coordinator
        webView.loadFileURL(url, allowingReadAccessTo: url)
        try await waitUntil("location.protocol === 'file:' && document.documentElement.dataset.guideReady === 'true' && document.readyState === 'complete' && document.fonts.status === 'loaded'", in: webView)
        return webView
    }

    private func expectNoErrors(in webView: WKWebView) async throws {
        #expect(try await webView.evaluateJavaScript("window.guideErrors") as? [String] == [])
    }

    private func waitUntil(_ condition: String, in webView: WKWebView) async throws {
        try await waitUntil { (try? await webView.evaluateJavaScript(condition)) as? Bool == true }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("Bundled guide did not become ready")
        throw GuideTestError.timeout
    }

    private enum GuideTestError: Error { case timeout }
}
