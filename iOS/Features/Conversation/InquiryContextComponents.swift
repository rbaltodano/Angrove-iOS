//
//  InquiryContextComponents.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

struct UploadedFileStrip: View {
    let files: [UploadedFile]
    var alignment: Alignment = .center
    var onRemove: ((UploadedFile) -> Void)? = nil
    @State private var stripWidth: CGFloat = 0

    var body: some View {
        if !files.isEmpty {
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    ForEach(files) { file in
                        UploadedFileThumbnail(file: file, onRemove: onRemove.map { remove in
                            { remove(file) }
                        })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .frame(minWidth: stripWidth, alignment: alignment)
            }
            .scrollIndicators(.hidden)
            .frame(height: 138)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
            .attachmentScrollRegion()
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

struct UploadedFileThumbnail: View {
    let file: UploadedFile
    var onRemove: (() -> Void)? = nil

    private var thumbnailSize: CGSize {
        guard file.imageData != nil, let image = file.image else {
            return CGSize(width: 76, height: 92)
        }

        let scale = min(150 / image.size.width, 92 / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    var body: some View {
        // Thumbnail size, border thickness, and shadow are tuned here.
        ZStack(alignment: .topTrailing) {
            ZStack {
                AttachmentPreview(file: file) {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .sfSymbolDrawOn()
                        Text(file.name)
                            .font(.system(size: 8, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                    .foregroundColor(AngroveTheme.Colors.secondaryMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AngroveTheme.Colors.cardRaised)
                }
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(5)
            .background(AngroveTheme.Colors.uploadBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: AngroveTheme.Colors.mediaShadow, radius: 18, x: 0, y: 10)

            if let onRemove {
                Button(action: {
                    withAnimation(.springLively) {
                        onRemove()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AngroveTheme.Colors.deepSurface)
                        .frame(width: 22, height: 22)
                        .background(AngroveTheme.Colors.uploadBorder)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
                        .shadow(color: AngroveTheme.Colors.mediaShadow, radius: 8, x: 0, y: 4)
                        .frame(width: AngroveTheme.Spacing.controlHeight, height: AngroveTheme.Spacing.controlHeight)
                        .contentShape(Rectangle())
                }
                .offset(x: 18, y: -18)
                .accessibilityLabel("Remove \(file.name)")
                .buttonStyle(.plain)
            }
        }
        .rotationEffect(.degrees(file.rotationDegrees))
        .accessibilityLabel(file.name)
    }
}

/// Window coordinates let both shell and canvas navigation yield to attachment scrolling.
struct AttachmentScrollBoundsKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }

    static func contains(_ point: CGPoint, in bounds: [CGRect]) -> Bool {
        bounds.contains { $0.contains(point) }
    }
}

extension View {
    func attachmentScrollRegion() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AttachmentScrollBoundsKey.self,
                    value: [geometry.frame(in: .global)]
                )
            }
        }
    }
}

/// Gesture hit testing needs current screen coordinates, but those coordinates are not
/// presentation state. Updating them while scrolling must not invalidate the thread or shell.
@MainActor
final class AttachmentScrollRegions {
    private(set) var frames: [CGRect] = []

    func update(_ frames: [CGRect]) { self.frames = frames }

    func contains(_ point: CGPoint) -> Bool {
        AttachmentScrollBoundsKey.contains(point, in: frames)
    }
}
