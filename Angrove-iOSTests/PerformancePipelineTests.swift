import Foundation
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Performance pipeline regressions")
struct PerformancePipelineTests {
    @Test("Streaming guard matches the batch guard across arbitrary token boundaries")
    func incrementalGuardParity() {
        let phrase = "one two three four five six seven eight nine ten eleven twelve "
        let cases = [
            phrase + "ordinary unrepeated ending.",
            phrase + phrase,
            phrase + "\r\n" + phrase,
            phrase + ".\u{301}" + phrase,
            "This sentence has enough normalized characters to trigger the sentence guard. This sentence has enough normalized characters to trigger the sentence guard.",
            "日本語かな漢字中文العربية한국어 " + phrase,
            "One TWO three-four five, six seven eight nine ten. ONE two three four five six seven eight nine ten!",
            "Short. Short. --- \n" + phrase,
            "é e\u{301} 日本語 😀 " + phrase + phrase
        ]
        for text in cases {
            for chunkSize in [1, 2, 7, 19, 500] {
                var guardState = IncrementalGenerationGuard()
                var accumulated = ""
                let characters = text.unicodeScalars.map(String.init)
                for start in stride(from: 0, to: characters.count, by: chunkSize) {
                    let delta = characters[start..<min(start + chunkSize, characters.count)].joined()
                    accumulated += delta
                    let result = guardState.append(delta)
                    #expect(result.corrupt == LiteRTGenerationGuard.hasMixedScriptCorruption(in: accumulated))
                    #expect(result.repetitionPrefix == LiteRTGenerationGuard.responseBeforeRepetition(in: accumulated))
                }
            }
        }
    }

    @Test("Collision broad phase covers every exact overlap and deduplicates candidates")
    func collisionCoverage() {
        var rectangles: [CGRect] = []
        for i in 0..<180 {
            rectangles.append(CGRect(x: (i * 317 % 2400) - 1200, y: (i * 193 % 1800) - 900,
                                     width: 30 + i % 350, height: 20 + i % 290))
        }
        for size: CGFloat in [32, 128, 256] {
            let pairs = SpatialCollisionIndex.pairs(for: rectangles, cellSize: size)
            let set = Set(pairs)
            #expect(set.count == pairs.count)
            for i in rectangles.indices {
                for j in rectangles.indices where j > i && rectangles[i].intersects(rectangles[j]) {
                    #expect(set.contains(.init(first: i, second: j)))
                }
            }
        }
        let sparse = (0..<100).map { CGRect(x: $0 * 1000, y: 0, width: 50, height: 50) }
        #expect(SpatialCollisionIndex.pairs(for: sparse).isEmpty)
    }

    @Test("Attachment previews downsample and reuse the same decoded pixels")
    @MainActor func thumbnailBounds() async throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000)).pngData { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let file = UploadedFile(name: "Large photo", imageData: png, rotationDegrees: 0)
        let image = try #require(await AttachmentThumbnailStore.shared.thumbnail(for: file))
        #expect(max(image.size.width, image.size.height) <= 1536)
        #expect(min(image.size.width, image.size.height) >= 276)
        #expect(image.size.width / image.size.height == 2)
        #expect(await AttachmentThumbnailStore.shared.thumbnail(for: file) === image)
        #expect(file.imageData == png)
    }
}

extension PerformancePipelineTests {
    @Test("Top-k retrieval preserves lexical priority, thresholds, source filters and ties")
    func exactRanking() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = (0..<90).map { i in
            ["text": i % 3 == 0 ? "grace nature required" : i % 2 == 0 ? "nature required" : "ordinary",
             "title": "Source", "sourceId": i % 2 == 0 ? "a" : "b", "chunkIndex": i] as [String: Any]
        }
        let metadata = root.appending(path: "passages.json")
        try JSONSerialization.data(withJSONObject: rows).write(to: metadata)
        var floats = [Float](repeating: 0, count: 90 * 384)
        for i in 0..<90 { floats[i * 384] = Float(i % 11) / 10 }
        let vectors = root.appending(path: "embeddings.bin")
        try floats.withUnsafeBytes { try Data($0).write(to: vectors) }
        let store = try OnDeviceGroundingStore(embeddingsURL: vectors, passagesURL: metadata)
        var query = [Float](repeating: 0, count: 384); query[0] = 1
        for sourceIDs: Set<String>? in [nil, ["a"], ["b"]] {
            for terms: Set<String> in [[], ["nature"], ["grace", "nature"]] {
                for required: Set<String> in [[], ["required"]] {
                    let expected = (0..<90).filter { i in
                        let text = rows[i]["text"] as! String
                        let matches = terms.filter { text.contains($0) }.count
                        return (sourceIDs == nil || sourceIDs!.contains(rows[i]["sourceId"] as! String))
                            && required.allSatisfy { text.contains($0) }
                            && (1 - floats[i * 384] <= 0.45 || (sourceIDs != nil && (terms.isEmpty || matches > 0)))
                    }.sorted { i, j in
                        let left = terms.filter { (rows[i]["text"] as! String).contains($0) }.count
                        let right = terms.filter { (rows[j]["text"] as! String).contains($0) }.count
                        if left != right { return left > right }
                        return floats[i * 384] > floats[j * 384]
                    }
                    let result = store.retrieve(queryEmbedding: query, k: 7, sourceIDs: sourceIDs,
                                                prioritizingTerms: terms, requiredTerms: required)
                    #expect(result.compactMap(\.corpusIndex) == Array(expected.prefix(7)))
                }
            }
        }
    }

    @Test("Queued tree saves are immediately readable, ordered, and durable at the barrier")
    func personalWriteOrdering() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "performance-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let file = InsightTreeLocalStateFileStore(rootDirectory: root, defaults: defaults)
        let worker = SerializedPersonalStore()
        for number in 0..<100 { worker.save(["position": number], key: "positions", store: file) }
        #expect(worker.load([String: Int].self, key: "positions", store: file) == ["position": 99])
        await worker.flush()
        #expect(file.load([String: Int].self, key: "positions") == ["position": 99])
        worker.invalidate()
        try FileManager.default.removeItem(at: root)
        #expect(worker.load([String: Int].self, key: "positions", store: file) == nil)
    }
}

extension PerformancePipelineTests {
    @MainActor
    @Test("Background graph preparation rejects obsolete bookmark revisions without scheduling labels")
    func backgroundGraphRevisions() async {
        let first = ConceptDefinition(word: "First", partOfSpeech: "", pronunciation: "", meaning: "Initial subject", example: "")
        let latest = ConceptDefinition(word: "Latest", partOfSpeech: "", pronunciation: "", meaning: "Current subject", example: "")
        let queue = ModelTaskQueue()
        let tree = InsightTreeViewModel(insights: [first], modelTasks: queue,
            embeddingProvider: PipelineEmbeddingProvider(), midpointStoreScope: UUID())
        tree.updateInsights([latest])
        await tree.prepareSemanticTree()
        #expect(tree.nodes.flatMap(\.insights).map(\.id) == [latest.id])
        #expect(tree.nodes.flatMap(\.insights).allSatisfy { $0.embeddingVersion == "pipeline.fixture.v1" })
        #expect(queue.allTasks.isEmpty)
    }

    @Test("The conversation cache keeps detached completion and a newer composer draft")
    func cachedConversationMerge() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = InquirySnapshotFileStore(rootDirectory: root)
        let worker = SerializedInquiryStore(makeStore: { file })
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [.user("Question", nil, []), .text("")]
        let conversation = InquiryConversation(branches: [branch])
        var snapshot = InquiryPersistenceSnapshot(conversations: [conversation], activeConversationID: conversation.id)
        worker.save(snapshot)
        worker.completeDetachedResponse(branchID: branch.id, conversationID: conversation.id,
            responseIndex: 1, annotatedText: "Completed answer", presentation: .init(responseIndex: 1, showsThinking: false, thinkingSummary: []))
        snapshot.conversations[0].branches[0].bottomQuestionText = "Next draft"
        worker.save(snapshot)
        #expect(worker.readCached()?.conversations[0].branches[0].activeChatBlocks[1] == .text("Completed answer"))
        #expect(worker.readCached()?.conversations[0].branches[0].bottomQuestionText == "Next draft")
        await worker.flushAsync()
        #expect(file.load() == worker.readCached())
    }
}

private struct PipelineEmbeddingProvider: EmbeddingProvider {
    var version: String { "pipeline.fixture.v1" }
    func embed(_ text: String) async -> [Double]? { [1, 0] }
}

extension PerformancePipelineTests {
    @Test("Concurrent first semantic requests share preparation and retain explicit fallback identity")
    func semanticPreparationFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.semantic.empty", "CFBundleName": "Fixture"],
                                          format: .xml, options: 0).write(to: root.appending(path: "Info.plist"))
        let bundle = try #require(Bundle(url: root))
        let service = SemanticAssetService(bundle: bundle)
        async let first = service.references(for: "Council of Nicaea", limit: 3)
        async let second = service.references(for: "Council of Nicaea", limit: 3)
        let results = await (first, second)
        #expect(results.0.map(\.id) == results.1.map(\.id))
        #expect(service.state == .embeddingFallback)
        #expect(service.version == NLEmbeddingProvider.version)
        let cancelled = Task { await service.embed("Cancelled obsolete bookmark") }
        cancelled.cancel()
        #expect(await cancelled.value == nil)
    }
}

extension PerformancePipelineTests {
    @Test("Conversation seeds share immediate cache reads and a durable ordered write barrier")
    func seedCacheOrdering() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "seeds-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = LocalInsightTreeSeedFileStore(fileURL: root.appending(path: "seeds.json"), defaults: defaults)
        let worker = SerializedPersonalStore()
        #expect(worker.loadSeeds(store: store).isEmpty)
        let seed = LocalInsightTreeSeed(id: UUID(), label: "Virtue", summary: "Moral habits", embedding: [1, 0], embeddingVersion: "fixture.v1", createdAt: Date())
        worker.saveSeeds(["one": [seed]], store: store)
        worker.saveSeeds(["two": [seed]], store: store)
        #expect(worker.loadSeeds(store: store) == ["two": [seed]])
        await worker.flush()
        #expect(store.load() == ["two": [seed]])
        worker.invalidate()
        #expect(worker.loadSeeds(store: store) == ["two": [seed]])
    }
}

extension PerformancePipelineTests {
    @Test("Unreadable seed payloads cannot fall through to legacy data or be overwritten", EncryptedProtectionIsolation())
    func seedCorruptionPreservesBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "seed-corruption-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = LocalInsightTreeSeedFileStore(fileURL: root.appending(path: "seeds.json"), defaults: defaults)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try EncryptedPersonalFile.write(Data("{\"unexpected\":17}".utf8), to: store.fileURL)
        let original = try Data(contentsOf: store.fileURL)
        #expect(store.load().isEmpty)
        #expect(PersonalDataProtection.isBlocked)
        #expect(throws: LocalDataEncryptionError.self) { try store.save([:]) }
        #expect(try Data(contentsOf: store.fileURL) == original)
    }
}
