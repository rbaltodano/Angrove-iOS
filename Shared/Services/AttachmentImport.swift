import Foundation

nonisolated enum AttachmentImport {
    /// Scope access for the entire read, including when the provider materializes a cloud file.
    /// Only publish lightweight attachment values back to the UI after the reads complete.
    static func read(_ urls: [URL], keepsUnsupportedFiles: Bool = true) async -> [UploadedFile] {
        let work = Task.detached(priority: .userInitiated) {
            var files: [UploadedFile] = []
            for url in urls {
                guard !Task.isCancelled else { return [] as [UploadedFile] }
                let file: UploadedFile? = autoreleasepool {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try? Data(contentsOf: url)
                    let image = data.flatMap { UploadedFile.isImageData($0) ? $0 : nil }
                    guard keepsUnsupportedFiles || image != nil else { return nil }
                    return UploadedFile(name: url.lastPathComponent, imageData: image, rotationDegrees: .random(in: -5...5))
                }
                if let file { files.append(file) }
            }
            return files
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }
}
