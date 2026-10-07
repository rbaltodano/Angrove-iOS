import SwiftUI

struct AttachmentPreview<Placeholder: View>: View {
    let file: UploadedFile
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
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
