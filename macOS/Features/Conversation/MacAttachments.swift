import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Image attachments above a question: removable in the composer, fixed in the transcript.
struct MacAttachmentStrip: View {
    let files: [UploadedFile]
    var onRemove: ((UUID) -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(files) { file in
                MacAttachmentThumbnail(file: file)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AngroveTheme.Colors.border, lineWidth: 1))
                    .rotationEffect(.degrees(file.rotationDegrees))
                    .overlay(alignment: .topTrailing) {
                        if let onRemove {
                            Button { onRemove(file.id) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .angroveIcon(.large)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(AngroveTheme.Colors.canvas, AngroveTheme.Colors.lightGreen)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove \(file.name)")
                            .help("Remove attachment")
                        }
                    }
                    .accessibilityLabel(file.name)
            }
        }
        .frame(maxWidth: MacConversationStyle.questionMaxWidth, alignment: .trailing)
    }
}

/// Downsamples off the main thread so large photos never decode at full size for a preview.
struct MacAttachmentThumbnail: View {
    let file: UploadedFile
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            AngroveTheme.Colors.canvasSecondary
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(AngroveTheme.Colors.placeholderText)
            }
        }
        .task(id: file.id) {
            guard let data = file.imageData else { return }
            image = await Task.detached(priority: .userInitiated) { Self.thumbnail(data) }.value
        }
    }

    nonisolated private static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 288
        ] as CFDictionary)
    }
}

/// Presents the Photos and Finder pickers behind the dock's attachment menu.
/// Only readable images are kept: the model reads image content, not other file types.
struct MacAttachmentPickers: ViewModifier {
    @Binding var showsFiles: Bool
    @Binding var showsPhotos: Bool
    let onAttach: ([UploadedFile]) -> Void
    @State private var photoItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    let files = await AttachmentImport.read(urls, keepsUnsupportedFiles: false)
                    guard !Task.isCancelled, !files.isEmpty else { return }
                    onAttach(files)
                }
            }
            .photosPicker(isPresented: $showsPhotos, selection: $photoItems, maxSelectionCount: 8, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var files: [UploadedFile] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), UploadedFile.isImageData(data) {
                            files.append(UploadedFile(name: "Photo", imageData: data, rotationDegrees: .random(in: -5...5)))
                        }
                    }
                    photoItems = []
                    if !files.isEmpty { onAttach(files) }
                }
            }
    }
}
