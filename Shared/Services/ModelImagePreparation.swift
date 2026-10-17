import Foundation

/// Original attachments remain immutable. Only normalized model inputs are cached, with a
/// pixel/data budget, so later turns do not decode and encode the same photos on the main actor.
nonisolated final class ModelImagePreparation: @unchecked Sendable {
    static let shared = ModelImagePreparation()
    private let queue = DispatchQueue(label: "com.angrove.model-images", qos: .userInitiated)
    private let cache = NSCache<NSUUID, NSData>()

    init() {
        cache.countLimit = 32
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(for file: UploadedFile) -> Data? {
        cache.object(forKey: file.id as NSUUID).map { $0 as Data }
    }

    func prepare(_ context: ConversationContext) async {
        let files = context.transcript.flatMap { block -> [UploadedFile] in
            if case .user(_, _, let uploads) = block { return uploads }
            return []
        }
        guard !files.isEmpty, !Task.isCancelled else { return }
        let request = ImagePreparationRequest()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    for file in files {
                        guard !request.isCancelled else { break }
                        guard cachedImage(for: file) == nil, let original = file.imageData else { continue }
                        autoreleasepool {
                            if let image = UploadedFile.normalizedModelImageData(original) {
                                cache.setObject(image as NSData, forKey: file.id as NSUUID, cost: image.count)
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        } onCancel: { request.cancel() }
    }
}

private nonisolated final class ImagePreparationRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
