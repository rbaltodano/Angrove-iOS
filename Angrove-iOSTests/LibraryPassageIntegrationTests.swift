import Foundation
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Library passage integration", .serialized, EncryptedProtectionIsolation())
struct LibraryPassageIntegrationTests {
    @Test("Old Insights decode without being mistaken for Library passages")
    func legacyInsightCompatibility() throws {
        let original = ConceptDefinition(word: "Justice", partOfSpeech: "", pronunciation: "", meaning: "Give each their due", example: "")
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        payload.removeValue(forKey: "isLibraryQuote")
        payload.removeValue(forKey: "libraryAttribution")
        let restored = try JSONDecoder().decode(ConceptDefinition.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(restored == original)
        #expect(!restored.isLibraryQuote)
    }

    @Test("A clipped passage retains its identity, quote and attribution through protected migration")
    func clippedPassageMigration() throws {
        let suite = "AngrovePassageIntegration.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let passage = ConceptDefinition(word: "Confessions", partOfSpeech: "", pronunciation: "", meaning: "Our heart is restless.", example: "", isLibraryQuote: true, libraryAttribution: "— Augustine of Hippo, ~397–400 CE")
        let key = "aquinas.library.clipped-passages.v1"
        defaults.set(try JSONEncoder().encode([passage]), forKey: key)
        let store = InsightTreeLocalStateFileStore(rootDirectory: root, defaults: defaults)
        #expect(store.load([ConceptDefinition].self, key: key) == [passage])
        #expect(defaults.object(forKey: key) == nil)
        let bytes = try Data(contentsOf: store.url(for: key))
        #expect(LocalDataCipher.isEncrypted(bytes))
        #expect(!String(decoding: bytes, as: UTF8.self).contains(passage.meaning))
        #expect(store.load([ConceptDefinition].self, key: key) == [passage])
    }

    @MainActor
    @Test("Selected reader text adds Ask alongside the native Copy menu")
    func readerSelectionMenu() throws {
        let reader = AskingTextView()
        reader.text = "Selected passage and the remaining paragraph."
        let end = try #require(reader.position(from: reader.beginningOfDocument, offset: 16))
        let range = try #require(reader.textRange(from: reader.beginningOfDocument, to: end))
        let copy = UIAction(title: "Copy") { _ in }
        let menu = try #require(reader.editMenu(for: range, suggestedActions: [copy]))
        #expect((menu.children.first as? UIAction)?.title == "Ask")
        #expect(menu.children.contains { ($0 as? UIAction)?.title == "Copy" })
    }

    @MainActor
    @Test("Provenance uses a book-specific estimate and an explicit unknown fallback")
    func passageAttribution() {
        #expect(LibraryWorkAttribution.line(workID: "augustine-confessions") == "— Augustine of Hippo, ~397–400 CE")
        #expect(LibraryWorkAttribution.line(workID: "web-bible", bibleBook: "Genesis") != "— Unknown")
        #expect(LibraryWorkAttribution.line(workID: "unlisted-work") == "— Unknown")
    }
}
