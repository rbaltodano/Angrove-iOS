import Photos
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Recent photo callbacks")
@MainActor
struct RecentPhotoCallbacksTests {
    @Test("Background thumbnail delivery reaches the main actor and ignores cancellation")
    func thumbnailDelivery() async {
        let expected = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let (stream, continuation) = AsyncStream<UIImage?>.makeStream()
        let callback = RecentPhotoCallbacks.image { image in
            MainActor.assertIsolated()
            continuation.yield(image)
        }

        await Task.detached {
            callback(nil, [PHImageCancelledKey: true])
            callback(expected, [PHImageResultIsDegradedKey: true])
            callback(expected, [PHImageResultIsDegradedKey: false])
        }.value

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first.flatMap { $0 } === expected)
        #expect(second.flatMap { $0 } === expected)
        continuation.finish()
    }

    @Test("Background selection delivery preserves data and cancellation", arguments: [false, true])
    func selectionDelivery(cancelled: Bool) async {
        let expected = cancelled ? nil : Data([1, 2, 3])
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let callback = RecentPhotoCallbacks.imageData { data, wasCancelled in
            MainActor.assertIsolated()
            #expect(data == expected)
            #expect(wasCancelled == cancelled)
            continuation.yield(true)
            continuation.finish()
        }

        await Task.detached {
            callback(expected, nil, .up, [PHImageCancelledKey: cancelled])
        }.value

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }
}
