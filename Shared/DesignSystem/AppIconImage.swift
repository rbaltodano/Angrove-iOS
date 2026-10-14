import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// The app icon image: the painted leaf from the app icon, cropped tight for inline marks.
struct AppIconImage: View {
    static let assetName = "AppIconImage"

    #if canImport(AppKit)
    @MainActor private static let macImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: assetName, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    #endif

    var size: CGFloat

    var body: some View {
        artwork
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var artwork: Image {
        #if canImport(AppKit)
        if let image = Self.macImage { return Image(nsImage: image) }
        #endif
        return Image(Self.assetName)
    }
}
