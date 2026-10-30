import Foundation
import Testing
import WebKit
@testable import AngroveMac

/// The bundled guide is written for iPhone; the Mac swaps in its own copy when the page loads.
@MainActor
struct MacUserGuideCopyTests {
    @Test func everyOverrideTargetsAGuideTopic() {
        for id in MacUserGuideCopy.overrides.keys {
            #expect(UserGuideTopic.topic(id: id) != nil, "\(id) is not a guide topic")
        }
    }

    @Test func macPageDescribesMacSettingsAndControls() async throws {
        var text = try await renderedGuideText(topicID: nil)
        for topic in UserGuideTopic.all {
            text += try await renderedGuideText(topicID: topic.id)
        }
        #expect(!text.contains("haptics"))
        #expect(!text.contains("alignment"))
        #expect(!text.contains("Face ID"))
        #expect(!text.contains("your phone"))
        #expect(!text.contains("Tap "))
        #expect(!text.contains("iOS version"))
        #expect(text.contains("Touch ID or your Mac password"))
        #expect(text.contains("Conversations sets the response and question fonts"))
        #expect(text.contains("Click an underlined term"))
        #expect(text.contains("press Command-M"))
    }

    @Test func hintsWrittenAfterLoadAreConverted() async throws {
        let webView = try await loadedGuide(topicID: "definitions")
        let text = try await webView.callAsyncJavaScript("""
            const hint = document.createElement('p');
            document.body.appendChild(hint);
            hint.textContent = 'Tap the citation, from the Library on your phone.';
            await new Promise(resolve => setTimeout(resolve, 0));
            return hint.textContent;
            """, contentWorld: .page) as? String
        #expect(text == "Click the citation, from the Library on your Mac.")
    }

    private func renderedGuideText(topicID: String?) async throws -> String {
        let webView = try await loadedGuide(topicID: topicID)
        return try #require(try await webView.evaluateJavaScript("document.body.innerText") as? String)
    }

    /// The page keeps only the chosen topic's article, as in `MacUserGuideView`.
    private func loadedGuide(topicID: String?) async throws -> WKWebView {
        let url = try #require(Bundle.main.url(forResource: "UserGuide", withExtension: "html"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let topic = topicID.map { "'\($0)'" } ?? "null"
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.guideContext = { topicID: \(topic), nativeScrolling: true };",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(
            source: MacUserGuideCopy.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let loaded = LoadWaiter()
        webView.navigationDelegate = loaded
        webView.loadFileURL(url, allowingReadAccessTo: url)
        try await loaded.wait()
        return webView
    }
}

@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    func wait() async throws {
        if finished { return }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finished = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
