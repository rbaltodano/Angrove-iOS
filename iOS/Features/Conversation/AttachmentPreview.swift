import SwiftUI

struct AttachmentPreview<Placeholder: View>: View {
    let file: UploadedFile
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            // Fit within the caller's preview bounds so portrait and landscape photos keep
            // their original proportions instead of being cropped to the thumbnail frame.
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
            else { placeholder() }
        }
        .task(id: file.id) {
            thumbnail = nil
            let image = await AttachmentThumbnailStore.shared.thumbnail(for: file)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
    }
}
