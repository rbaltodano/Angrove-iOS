import SwiftUI

/// The Worktree page: saved Worktrees as cards, opening onto the canvas.
struct MacWorktreeHomeView: View {
    let library: WorktreeLibrary
    let queuePopup: ModelTasksPopupState
    @State private var pendingDelete: WorktreeDocument?
    @State private var pendingRename: WorktreeDocument?
    @State private var renameTitle = ""
    @State private var searchText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let board = library.openBoard {
            MacWorktreeView(board: board, queuePopup: queuePopup, onSave: { library.save(board) })
                .id(board.documentID)
                .overlay(alignment: .topLeading) {
                    MacBackCapsule(title: String(localized: "Boards"), leavesOnEscape: false) {
                        withAnimation(reduceMotion ? nil : .springStandard) { library.close() }
                    }
                }
                .transition(.opacity)
        } else {
            list.transition(.opacity)
        }
    }

    private var stats: [MacCollectionStat] {
        let documents = library.documents
        guard !documents.isEmpty else { return [] }
        let items = documents.reduce(0) { $0 + $1.items.count }
        let windows = documents.reduce(0) { $0 + $1.items.filter { $0.branches != nil }.count }
        return [
            MacCollectionStat(documents.count, "Board", "Boards"),
            MacCollectionStat(items, "Item", "Items"),
            MacCollectionStat(windows, "Conversation", "Conversations")
        ]
    }

    private var visibleDocuments: [WorktreeDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.sortedDocuments }
        return library.sortedDocuments.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) }
    }

    private var list: some View {
        MacCollectionScrollPage(artwork: .boards) {
            MacCollectionHeader(title: "Boards",
                description: "Lay out notes, questions, images and whole conversations side by side, and arrange them as your thinking takes shape.",
                stats: stats)
                // New Board is the dashed card in the grid; the shortcut stays with the page.
                .background {
                    Button("New Board", action: create)
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

            VStack(alignment: .leading, spacing: 24) {
                if !library.documents.isEmpty {
                    MacCollectionSearchBar(title: String(localized: "All Boards"), searchText: $searchText,
                                           prompt: Text("Search Boards"))
                }
                if !searchText.isEmpty, visibleDocuments.isEmpty {
                    Text("No Boards match “\(searchText)”.")
                        .paragraphFont()
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: MacCollectionLayout.gridSpacing, alignment: .top)],
                              spacing: MacCollectionLayout.gridSpacing) {
                        ForEach(visibleDocuments) { document in
                            WorktreeCard(document: document,
                                onOpen: { withAnimation(reduceMotion ? nil : .springStandard) { library.open(document.id) } },
                                onDelete: { pendingDelete = document },
                                onRename: { renameTitle = document.displayTitle; pendingRename = document })
                                .macInsightDropDestination(open: { library.open(document.id) })
                        }
                        if searchText.isEmpty {
                            WorktreeNewCard(isFirst: library.documents.isEmpty, action: create)
                        }
                    }
                }
            }
        }
        .alert("Rename Board", isPresented: Binding(get: { pendingRename != nil }, set: { if !$0 { pendingRename = nil } })) {
            TextField("Board name", text: $renameTitle)
            Button("Cancel", role: .cancel) { pendingRename = nil }
            Button("Rename") {
                if let document = pendingRename { library.rename(document.id, to: renameTitle) }
                pendingRename = nil
            }
            .disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Board?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let document = pendingDelete { withAnimation(.springStandard) { library.delete(document.id) } }
                pendingDelete = nil
            }
        } message: {
            Text("Its notes, cards and conversation windows are removed. Conversations in the sidebar stay.")
        }
    }

    private func create() {
        withAnimation(reduceMotion ? nil : .springStandard) { library.create() }
    }
}

/// A saved Board using the conversation collection card style, without a canvas preview.
private struct WorktreeCard: View {
    let document: WorktreeDocument
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void
    @State private var isHovered = false

    private var summary: String {
        let windows = document.items.filter { $0.branches != nil }.count
        let count = document.items.count
        let items = count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
        return windows > 0 ? items + " · " + (windows == 1 ? String(localized: "1 conversation")
            : String(localized: "\(windows) conversations")) : items
    }

    private var menuEntries: [MacMenuEntry] { [
        MacMenuEntry("Open", symbol: "arrow.up.right", action: onOpen),
        MacMenuEntry("Rename", symbol: "pencil.line", action: onRename), .divider,
        MacMenuEntry("Delete", symbol: "trash", destructive: true, action: onDelete)
    ] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 8)
                MacActionMenu(entries: { menuEntries }) { MacCollectionCardOptionsLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Board options")
            }
            .frame(height: AngroveTheme.Spacing.controlHeight)

            Text(document.displayTitle)
                .font(AngroveTheme.Typography.uiHeading)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .lineSpacing(3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                Text(MacCollectionDate.short(document.updatedAt))
                Text(verbatim: "·")
                Text(summary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .opacity(isHovered ? 1 : 0)
                    .offset(x: isHovered ? 0 : -4, y: isHovered ? 0 : 4)
            }
            .font(AngroveTheme.Typography.chipLabel)
            .foregroundStyle(AngroveTheme.Colors.placeholderText)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .macCollectionCard()
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .animation(.springQuick, value: isHovered)
        .macCardHover()
        .macContextMenu { menuEntries }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open"), onOpen)
    }
}

/// The blank board at the end of the grid.
private struct WorktreeNewCard: View {
    let isFirst: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .frame(width: 48, height: 48)
                    .background(AngroveTheme.Colors.canvasSecondary, in: Circle())
                    .overlay(Circle().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
                Text(isFirst ? "Make your first Board" : "New Board")
                    .font(AngroveTheme.Typography.heading)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                Text("Type / on the canvas for commands.")
                    .font(AngroveTheme.Typography.chipLabel)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .background {
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    .strokeBorder(AngroveTheme.Colors.controlBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            }
            .contentShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .macCardHover()
    }
}

/// A miniature of a board on the dotted canvas: its rendered snapshot when there is one, else its
/// items drawn as simple shapes while the snapshot renders.
struct WorktreeThumbnail: View {
    let items: [WorktreeStoredItem]
    var snapshot: WorktreeSnapshot?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let image = snapshot?.image(for: colorScheme)
        Canvas { context, size in
            drawDots(in: &context, size: size)
            guard image == nil else { return }
            let shapes = items.map(WorktreeThumbnailShape.init)
            guard let bounds = shapes.map(\.frame).reduce(nil, { $0?.union($1) ?? $1 }) else { return }
            let inset: CGFloat = 20
            let scale = min((size.width - inset * 2) / max(bounds.width, 1),
                            (size.height - inset * 2) / max(bounds.height, 1), 0.32)
            let offset = CGPoint(x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                                 y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
            for shape in shapes {
                let frame = CGRect(x: shape.frame.minX * scale + offset.x, y: shape.frame.minY * scale + offset.y,
                                   width: shape.frame.width * scale, height: shape.frame.height * scale)
                draw(shape.kind, in: frame, context: &context)
            }
        }
        .background(AngroveTheme.Colors.canvas)
        .overlay {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .transition(.opacity)
            } else if items.isEmpty {
                Text("Empty board")
                    .font(AngroveTheme.Typography.chipLabel)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: image != nil)
        .accessibilityHidden(true)
    }

    private func drawDots(in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 14
        let dot = AngroveTheme.Colors.dotGrid(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.14)
        var path = Path()
        var y = spacing / 2
        while y < size.height {
            var x = spacing / 2
            while x < size.width {
                path.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                x += spacing
            }
            y += spacing
        }
        context.fill(path, with: .color(dot))
    }

    private func draw(_ kind: WorktreeThumbnailShape.Kind, in frame: CGRect, context: inout GraphicsContext) {
        let ink = AngroveTheme.Colors.primaryReadable
        switch kind {
        case .window:
            let card = Path(roundedRect: frame, cornerRadius: min(8, frame.width / 6), style: .continuous)
            context.fill(card, with: .color(AngroveTheme.Colors.canvasSecondary))
            context.stroke(card, with: .color(AngroveTheme.Colors.controlBorder), lineWidth: 1)
            let titleBar = CGRect(x: frame.minX + frame.width * 0.12, y: frame.minY + frame.height * 0.1,
                                  width: frame.width * 0.55, height: max(2, frame.height * 0.05))
            context.fill(Path(roundedRect: titleBar, cornerRadius: titleBar.height / 2), with: .color(AngroveTheme.Colors.lightGreen))
            drawLines(in: CGRect(x: frame.minX + frame.width * 0.12, y: frame.minY + frame.height * 0.26,
                                 width: frame.width * 0.76, height: frame.height * 0.6),
                      count: 5, color: ink.opacity(0.18), context: &context)
        case .image:
            let card = Path(roundedRect: frame, cornerRadius: min(6, frame.width / 6), style: .continuous)
            context.fill(card, with: .color(AngroveTheme.Colors.lightGreen.opacity(0.3)))
            var hill = Path()
            hill.move(to: CGPoint(x: frame.minX, y: frame.maxY))
            hill.addLine(to: CGPoint(x: frame.minX + frame.width * 0.35, y: frame.minY + frame.height * 0.5))
            hill.addLine(to: CGPoint(x: frame.minX + frame.width * 0.6, y: frame.minY + frame.height * 0.75))
            hill.addLine(to: CGPoint(x: frame.minX + frame.width * 0.8, y: frame.minY + frame.height * 0.6))
            hill.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
            hill.closeSubpath()
            var clipped = context
            clipped.clip(to: card)
            clipped.fill(hill, with: .color(AngroveTheme.Colors.lightGreen.opacity(0.55)))
        case .insight:
            let card = Path(roundedRect: frame, cornerRadius: min(8, frame.height / 3), style: .continuous)
            context.fill(card, with: .color(AngroveTheme.Colors.canvasSecondary))
            context.stroke(card, with: .color(AngroveTheme.Colors.lightGreen), lineWidth: 1)
            drawLines(in: frame.insetBy(dx: frame.width * 0.14, dy: frame.height * 0.25), count: 2,
                      color: AngroveTheme.Colors.lightGreen.opacity(0.6), context: &context)
        case .heading:
            let bar = CGRect(x: frame.minX, y: frame.midY - max(1.5, frame.height * 0.2),
                             width: frame.width, height: max(3, frame.height * 0.4))
            context.fill(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(ink.opacity(0.55)))
        case .text(let lines):
            drawLines(in: frame, count: lines, color: ink.opacity(0.28), context: &context)
        }
    }

    private func drawLines(in frame: CGRect, count: Int, color: Color, context: inout GraphicsContext) {
        guard count > 0 else { return }
        let step = frame.height / CGFloat(count)
        let thickness = max(1.5, min(3, step * 0.4))
        for line in 0..<count {
            let width = line == count - 1 && count > 1 ? frame.width * 0.6 : frame.width
            let rect = CGRect(x: frame.minX, y: frame.minY + step * CGFloat(line) + (step - thickness) / 2,
                              width: width, height: thickness)
            context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2), with: .color(color))
        }
    }
}

/// How a saved item reads in miniature, with an estimated world frame for items whose size
/// is only known once laid out.
struct WorktreeThumbnailShape {
    enum Kind: Equatable { case window, image, insight, heading, text(lines: Int) }

    let kind: Kind
    let frame: CGRect

    init(_ item: WorktreeStoredItem) {
        let size: CGSize
        if item.branches != nil {
            kind = .window
            size = item.size ?? CGSize(width: WorktreeItemView.cardWidth, height: WorktreeItemView.cardMaxHeight)
        } else if item.image != nil {
            kind = .image
            size = item.size ?? item.photoLayout?.contentSize ?? CGSize(width: 240, height: 180)
        } else if item.insight != nil || item.isHelp == true {
            kind = .insight
            size = item.size ?? CGSize(width: 320, height: 120)
        } else if item.isHeading {
            kind = .heading
            let width = min(max(CGFloat(item.text.count) * 16, 80), 640)
            size = item.size ?? CGSize(width: width, height: 44)
        } else {
            let characters = CGFloat(max(item.text.count, 8))
            let width = item.size?.width ?? min(characters * 7.5, 360)
            let lines = Int(min(8, max(1, (characters * 7.5 / max(width, 1)).rounded(.up))))
            kind = .text(lines: lines)
            size = item.size ?? CGSize(width: width, height: CGFloat(lines) * 22)
        }
        frame = CGRect(origin: item.origin, size: size)
    }
}
