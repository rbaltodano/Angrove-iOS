import SwiftUI

/// The app icon image: the painted leaf from the app icon, cropped tight for inline marks.
struct AppIconImage: View {
    static let assetName = "AppIconImage"

    var size: CGFloat

    var body: some View {
        Image(Self.assetName)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
