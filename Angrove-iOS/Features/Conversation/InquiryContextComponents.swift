//
//  InquiryContextComponents.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

// MARK: - Context Chips

/// Small locked/removable pill above a question. Used for insights and response forks.
struct BranchContextChip: View {
    let title: String
    let icon: String
    var animationKey: String = "static"
    var isFilled: Bool = false
    var fillColor: Color = AngroveTheme.Colors.canvasSecondary
    var appearDelay: TimeInterval = 0
    var animatesAppearance: Bool = true
    var showRemove: Bool = false
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    /// When true: no padding, no background, no border — just icon + text.
    var isMinimal: Bool = false
    @State private var borderDrawProgress: CGFloat = 0
    @State private var isVisible: Bool = false

    private var isInsightChip: Bool {
        icon == "text.bubble" || icon == "text.bubble.fill"
    }

    private var labelContents: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: isInsightChip ? 14 : 12, weight: .bold))
                .foregroundColor(AngroveTheme.Colors.darkGreen)
                .rotationEffect(icon == "arrow.triangle.branch" ? .degrees(90) : .degrees(0))
                .id(icon)
                .sfSymbolDrawOn(delay: appearDelay + 0.25)
            Text(title)
                .font(isInsightChip ? .figtreeHeading2 : .figtreeChipLabel)
                .foregroundColor(AngroveTheme.Colors.darkGreen)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var mainRegion: some View {
        if let onTap {
            Button(action: onTap) {
                paddedLabelContents
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title) Insight")
        } else {
            paddedLabelContents
        }
    }

    private var paddedLabelContents: some View {
        labelContents
            .padding(.leading, isMinimal ? 0 : 20)
            .padding(.trailing, showRemove ? 10 : (isMinimal ? 0 : 20))
            .padding(.vertical, isMinimal ? 0 : 16)
            .contentShape(Rectangle())
    }

    var body: some View {
        HStack(spacing: 0) {
            mainRegion

            if showRemove, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AngroveTheme.Colors.darkGreen)
                        .sfSymbolDrawOn()
                }
                .buttonStyle(.plain)
                .padding(.trailing, isMinimal ? 0 : 20)
                .padding(.vertical, isMinimal ? 0 : 16)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .background(isFilled && !isMinimal ? fillColor : Color.clear)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.5)
                .trim(from: 0, to: isMinimal ? 0 : borderDrawProgress)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear(perform: revealChip)
        .onChange(of: animationKey) { oldValue, newValue in
            if !isMinimal { drawBorder() }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func revealChip() {
        guard animatesAppearance else {
            isVisible = true
            borderDrawProgress = isMinimal ? 0 : 1
            return
        }

        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + appearDelay) {
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = true
            }
            if !isMinimal { drawBorder() }
        }
    }

    private func drawBorder() {
        borderDrawProgress = 0
        withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
            borderDrawProgress = 1
        }
    }
}

// MARK: - Connection Context Chip

struct ConnectionContextChip: View {
    let concepts: [ConceptDefinition]
    var onRemove: (() -> Void)? = nil
    @State private var borderDrawProgress: CGFloat = 0
    @State private var isVisible: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AngroveTheme.Colors.darkGreen)

            Text(concepts.map { $0.word.capitalized }.formatted())
                .font(.figtreeHeading2)
                .foregroundColor(AngroveTheme.Colors.darkGreen)
                .lineLimit(2)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AngroveTheme.Colors.darkGreen)
                        .sfSymbolDrawOn()
                }
                .padding(.leading, 4)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.5)
                .trim(from: 0, to: borderDrawProgress)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { isVisible = true }
            withAnimation(.easeOut(duration: 0.55).delay(0.05)) { borderDrawProgress = 1 }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Uploaded File Thumbnails

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
            .frame(width: 76, height: 92)
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
