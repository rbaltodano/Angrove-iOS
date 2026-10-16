import SwiftUI

/// The Tools card, docked above the controls: every way to add or act on something, with its
/// commands and shortcut. Clicking a row picks that tool up to place on the canvas.
struct WorktreeToolsCard: View {
    let onChoose: (WorktreeTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(WorktreeTool.cardTools) { tool in
                WorktreeToolRow(tool: tool) { onChoose(tool) } label: { row(tool) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
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

/// A Tools row: highlighted on hover like a row of the "…" menu, so it reads as clickable.
private struct WorktreeToolRow<Label: View>: View {
    let tool: WorktreeTool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 8)
                .background(isHovered ? AngroveTheme.Colors.systemSelection : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityHint(tool.needsTarget ? "Click something on the canvas" : "Click the canvas to place it")
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

/// A picked-up tool following the pointer: a label like the controls' hover labels saying what a
/// click does, trailing on the photo's spring. A click places it; dragging or scrolling pans.
struct WorktreeToolPlacement: View {
    let tool: WorktreeTool
    /// The canvas zoom, so placed text previews at the size it will land.
    let scale: CGFloat
    /// The click, and where the preview's top-leading corner sat, in the view's coordinates.
    let onPlace: (_ click: CGPoint, _ origin: CGPoint) -> Void
    var onPan: (CGSize) -> Void = { _ in }
    @State private var pointer: CGPoint?
    @State private var position = CGPoint.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Placed material starts 16pt right of the pointer with its first line centred on it, as
    /// typing on the canvas does; the label sits there too.
    private func origin(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + 16, y: point.y - firstLineHeight / 2)
    }

    private var firstLineHeight: CGFloat {
        switch tool {
        case .heading: Self.headingLineHeight * scale
        case .text, .question: WorktreeTextEditor.lineHeight * scale
        default: WorktreeTextEditor.lineHeight
        }
    }

    private static let headingLineHeight: CGFloat = 56
    /// The hover label's height.
    private static let labelHeight: CGFloat = 36

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorktreePhotoPointerSurface(onMove: follow, onPlace: { onPlace($0, origin(for: $0)) }, onPan: onPan)
            if pointer != nil {
                MacModelControlHoverLabel(help: MacModelControlHelp(title: tool.placementPrompt, shortcut: nil))
                    .offset(x: position.x + 16, y: position.y - Self.labelHeight / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text("\(tool.placementPrompt). Press Escape to cancel."))
    }

    private func follow(_ next: CGPoint?) {
        guard let next else { pointer = nil; return }
        // Trails the pointer on a spring once it has appeared; jumps there on the first move.
        let isFollowing = pointer != nil
        pointer = next
        if isFollowing {
            withAnimation(reduceMotion ? nil : .springLively) { position = next }
        } else {
            position = next
        }
    }
}
