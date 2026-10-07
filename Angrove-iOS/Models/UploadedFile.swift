//
//  UploadedFile.swift
//  Angrove-iOS
//

import ImageIO
import UIKit

/// File/image selected before submitting a question.
nonisolated struct UploadedFile: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let name: String
    let imageData: Data?
    let rotationDegrees: Double

    init(id: UUID = UUID(), name: String, imageData: Data?, rotationDegrees: Double) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.rotationDegrees = rotationDegrees
    }

    static func == (lhs: UploadedFile, rhs: UploadedFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension UploadedFile {
    /// Whether `data` holds a readable image, judged from its header without decoding pixels.
    nonisolated static func isImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// The attachment's image, decoded once and reused across redraws.
    @MainActor var image: UIImage? {
        UploadedFileImageCache.image(for: self)
    }
}

/// Decoded attachment images keyed by file ID. An `UploadedFile`'s data never changes, so its ID
/// is a stable key, and `NSCache` releases entries under memory pressure.
@MainActor
private enum UploadedFileImageCache {
    private static let images = NSCache<NSUUID, UIImage>()

    static func image(for file: UploadedFile) -> UIImage? {
        guard let data = file.imageData else { return nil }
        let key = file.id as NSUUID
        if let cached = images.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}

/// Background ImageIO decoding with a bounded pixel cache. Originals remain available for model
/// input and export; only the small UI previews are downsampled.
nonisolated final class AttachmentThumbnailStore: @unchecked Sendable {
    static let shared = AttachmentThumbnailStore()
    private let queue = DispatchQueue(label: "com.angrove.attachment-thumbnails", qos: .userInitiated)
    private let images = NSCache<NSUUID, UIImage>()
    private let maximumPixels = 1536

    init() {
        images.totalCostLimit = 16 * 1024 * 1024
        images.countLimit = 64
    }

    func thumbnail(for file: UploadedFile) async -> UIImage? {
        guard !Task.isCancelled, let data = file.imageData else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                let key = file.id as NSUUID
                if let image = images.object(forKey: key) { continuation.resume(returning: image); return }
                let image: UIImage? = PerformanceTrace.measure("Attachment Thumbnail") {
                    guard let source = CGImageSourceCreateWithData(data as CFData,
                        [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                    let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 1
                    let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 1
                    // Keep a 92pt aspect-fill crop sharp at @3x, subject to a fixed memory ceiling.
                    let aspect = max(width, height) / max(1, min(width, height))
                    let maxPixels = min(maximumPixels, max(384, Int(ceil(min(aspect, 100) * 276))))
                    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0,
                            [kCGImageSourceCreateThumbnailFromImageAlways: true,
                             kCGImageSourceCreateThumbnailWithTransform: true,
                             kCGImageSourceShouldCacheImmediately: true,
                             kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary) else { return nil }
                    let image = UIImage(cgImage: cgImage)
                    images.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
                    return image
                }
                continuation.resume(returning: image)
            }
        }
    }
}
