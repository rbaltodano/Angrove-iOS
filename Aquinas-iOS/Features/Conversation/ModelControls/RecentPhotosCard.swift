import Photos
import SwiftUI
import UIKit

/// The recent-photo shortcut shares the Context card's place in the bottom dock.
struct RecentPhotosCard: View {
    let onSelect: (Data) -> Void
    let onDismiss: () -> Void
    let onChoosePhoto: () -> Void
    @State private var library = RecentPhotosLibrary()
    @State private var dragY: CGFloat = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Select photo")
                .font(AquinasTheme.Typography.uiHeading)
                .foregroundStyle(AquinasTheme.Colors.headingText)
                .frame(maxWidth: .infinity)

            if library.isLoading {
                ProgressView()
                    .tint(AquinasTheme.Colors.lightGreen)
                    .frame(height: 80)
            } else if library.assets.isEmpty {
                VStack(spacing: 12) {
                    Text(library.canReadPhotos ? "No recent photos available." : "Choose a photo or allow photo access in Settings.")
                        .font(AquinasTheme.Typography.body)
                        .foregroundStyle(AquinasTheme.Colors.paragraphText)
                        .multilineTextAlignment(.center)
                    Button("Choose photo", action: onChoosePhoto)
                        .font(AquinasTheme.Typography.uiSubheading)
                        .foregroundStyle(AquinasTheme.Colors.lightGreen)
                        .frame(minHeight: AquinasTheme.Spacing.controlHeight)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(library.assets, id: \.localIdentifier) { asset in
                            Button {
                                library.select(asset, onSelect: onSelect)
                            } label: {
                                RecentPhotoThumbnail(asset: asset)
                                    .overlay {
                                        if library.selectedAssetID == asset.localIdentifier {
                                            ProgressView()
                                                .tint(AquinasTheme.Colors.headingText)
                                                .padding(12)
                                                .background(AquinasTheme.Colors.canvasSecondary, in: Circle())
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(library.selectedAssetID != nil)
                            .accessibilityLabel(Text("Photo from \(asset.creationDate ?? .distantPast, format: .dateTime.month().day().year())"))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 80)
            }

            if let error = library.error {
                Text(error)
                    .font(AquinasTheme.Typography.body)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: 355)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .offset(y: dragY)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    dragY = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > abs(value.translation.width),
                       value.translation.height > 100 || value.predictedEndTranslation.height > 180 {
                        onDismiss()
                    } else {
                        withAnimation(.springLively) { dragY = 0 }
                    }
                }
        )
        .accessibilityAction(.escape, onDismiss)
        .task { await library.load() }
        .onDisappear { library.cancelSelection() }
    }
}

@MainActor
@Observable
private final class RecentPhotosLibrary {
    var assets: [PHAsset] = []
    var isLoading = true
    var canReadPhotos = false
    var selectedAssetID: String?
    var error: String?
    private var selectionRequestID: PHImageRequestID?

    func load() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard !Task.isCancelled else { return }
        canReadPhotos = status == .authorized || status == .limited
        if canReadPhotos {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 10
            let result = PHAsset.fetchAssets(with: .image, options: options)
            assets = (0..<result.count).map { result.object(at: $0) }
        }
        isLoading = false
    }

    func select(_ asset: PHAsset, onSelect: @escaping (Data) -> Void) {
        guard selectedAssetID == nil else { return }
        error = nil
        selectedAssetID = asset.localIdentifier
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        selectionRequestID = PHImageManager.default().requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { [weak self] data, _, _, info in
            let cancelled = info?[PHImageCancelledKey] as? Bool == true
            Task { @MainActor in
                guard let self, self.selectedAssetID == asset.localIdentifier else { return }
                self.selectionRequestID = nil
                self.selectedAssetID = nil
                guard !cancelled, let data, UploadedFile.isImageData(data) else {
                    self.error = String(localized: "This photo couldn’t be loaded. Try another photo.")
                    return
                }
                onSelect(data)
            }
        }
    }

    func cancelSelection() {
        if let selectionRequestID { PHImageManager.default().cancelImageRequest(selectionRequestID) }
        selectionRequestID = nil
        selectedAssetID = nil
    }
}

private struct RecentPhotoThumbnail: View {
    let asset: PHAsset
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            AquinasTheme.Colors.canvas
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(AquinasTheme.Colors.placeholderText)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 80 * displayScale, height: 80 * displayScale),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                Task { @MainActor in image = result }
            }
        }
        .onDisappear {
            if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
            requestID = nil
        }
    }
}
