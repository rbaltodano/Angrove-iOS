import SwiftUI

/// The Tools card, docked above the controls: every way to add or act on something, with its
/// commands and shortcut. Clicking a row picks that tool up to place on the canvas.
struct WorktreeToolsCard: View {
    let onChoose: (WorktreeTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(WorktreeTool.allCases) { tool in
                Button { onChoose(tool) } label: { row(tool) }
                    .buttonStyle(.plain)
                    .accessibilityHint(tool == .file ? "Opens the file browser" : "Click the canvas to place it")
            }
        }
        .padding(28)
        .frame(width: 500, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1))
        .cardGlow()
    }

    private func row(_ tool: WorktreeTool) -> some View {
        HStack(spacing: 8) {
            Text(tool.title)
                .font(BrandTypography.font("Figtree-Bold", size: 14))
                .foregroundStyle(AngroveTheme.Colors.headingText)
            Spacer(minLength: 16)
            switch tool {
            case .text:
                hint("Type anything anywhere")
            case .question:
                hint("Type in quotes")
                WorktreeKeyChip { chipText("“") }
            default:
                if let command = tool.command {
                    WorktreeKeyChip { chipText(command.short) }
                    WorktreeKeyChip { chipText(command.full) }
                }
                if let shortcut = tool.shortcut {
                    WorktreeKeyChip {
                        Image(systemName: "command").font(.system(size: 11, weight: .bold))
                        if shortcut.shift { Image(systemName: "shift").font(.system(size: 10, weight: .bold)) }
                        chipText(shortcut.key.uppercased())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(shortcut.shift ? "Command Shift \(shortcut.key.uppercased())" : "Command \(shortcut.key.uppercased())"))
                }
            }
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(BrandTypography.font("Figtree-Regular", size: 14))
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
    }

    private func chipText(_ text: String) -> some View {
        Text(verbatim: text).font(BrandTypography.font("Figtree-Bold", size: 14))
    }
}

/// A command or key, in a light-green keycap.
private struct WorktreeKeyChip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .frame(height: 28)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AngroveTheme.Colors.lightGreen.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AngroveTheme.Colors.lightGreen.opacity(0.15), lineWidth: 1))
    }
}

/// A picked-up tool following the pointer, like a photo being placed: a 50% preview of what it
/// makes (or what to click), with the photo's spring trail and tilt. A click places it; dragging
/// or scrolling pans the canvas.
struct WorktreeToolPlacement: View {
    let tool: WorktreeTool
    /// The canvas zoom, so placed text previews at the size it will land.
    let scale: CGFloat
    /// The click, and where the preview's top-leading corner sat, in the view's coordinates.
    let onPlace: (_ click: CGPoint, _ origin: CGPoint) -> Void
    var onPan: (CGSize) -> Void = { _ in }
    @State private var pointer: CGPoint?
    @State private var position = CGPoint.zero
    @State private var tilt: Double = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Placed material starts 16pt right of the pointer with its first line centred on it, as
    /// typing on the canvas does.
    private func origin(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + 16, y: point.y - firstLineHeight / 2)
    }

    private var firstLineHeight: CGFloat {
        switch tool {
        case .heading: Self.headingLineHeight * scale
        case .rename: 40
        case .text, .question: WorktreeTextEditor.lineHeight * scale
        default: WorktreeTextEditor.lineHeight
        }
    }

    private static let headingLineHeight: CGFloat = 56

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorktreePhotoPointerSurface(onMove: follow, onPlace: { onPlace($0, origin(for: $0)) }, onPan: onPan)
            if pointer != nil {
                let at = origin(for: position)
                preview
                    .opacity(0.5)
                    .fixedSize()
                    .rotationEffect(.degrees(reduceMotion ? 2 : tilt), anchor: .leading)
                    .offset(x: at.x, y: at.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task(id: pointer) {
            guard pointer != nil else { return }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            withAnimation(reduceMotion ? nil : .springLively) { tilt = 2 }
        }
        .accessibilityLabel(Text(tool.needsTarget ? tool.placementPrompt : String(localized: "Click to place \(tool.title). Press Escape to cancel.")))
    }

    /// Styled as what the tool makes: a note, a heading, a label; or plain guidance to click.
    @ViewBuilder private var preview: some View {
        switch tool {
        case .heading:
            Text(tool.placementPrompt)
                .font(MacPageHeading.pageFont)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .frame(height: Self.headingLineHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(height: Self.headingLineHeight * scale, alignment: .topLeading)
        case .text, .question:
            Text(tool.placementPrompt)
                .font(BrandTypography.font("Figtree-Regular", size: 14))
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .frame(height: WorktreeTextEditor.lineHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(height: WorktreeTextEditor.lineHeight * scale, alignment: .topLeading)
        case .rename:
            Text(tool.placementPrompt)
                .font(.custom("LibreBaskerville-Italic", fixedSize: 28))
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .frame(height: 40)
        default:
            Text(tool.placementPrompt)
                .font(BrandTypography.font("Figtree-Regular", size: 14))
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .frame(height: WorktreeTextEditor.lineHeight)
        }
    }

    private func follow(_ next: CGPoint?) {
        guard let next else { pointer = nil; return }
        let previous = pointer
        pointer = next
        if let previous {
            withAnimation(reduceMotion ? nil : .springLively) {
                position = next
                if next.x != previous.x { tilt = next.x > previous.x ? 3 : 1 }
            }
        } else {
            position = next
        }
    }
}
