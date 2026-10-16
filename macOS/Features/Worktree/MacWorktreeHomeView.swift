import SwiftUI

/// The Worktree page: saved Worktrees as cards, opening onto the canvas.
struct MacWorktreeHomeView: View {
    let library: WorktreeLibrary
    let queuePopup: ModelTasksPopupState
    @State private var pendingDelete: WorktreeDocument?
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

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AngroveTheme.Spacing.cardPadding) {
                HStack(alignment: .firstTextBaseline) {
                    MacPageHeading(title: "Boards", font: MacPageHeading.pageFont)
                    Spacer()
                    Button("New Board", systemImage: "plus", action: create)
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                        .help("New Board (⇧⌘N)")
                }
                if library.documents.isEmpty {
                    AngroveEmptyState(systemImage: MacIcon.worktree.symbol, title: "Boards will gather here",
                        message: "A Board is an open canvas for notes, questions and commands. Make one to begin.")
                        .padding(.top, 48)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20, alignment: .top)], spacing: 20) {
                        ForEach(library.sortedDocuments) { document in
                            WorktreeCard(document: document,
                                onOpen: { withAnimation(reduceMotion ? nil : .springStandard) { library.open(document.id) } },
                                onDelete: { pendingDelete = document })
                        }
                    }
                }
            }
            .frame(maxWidth: MacConversationStyle.pageContentMaxWidth, alignment: .leading)
            .padding(.top, MacConversationStyle.pageTopPadding)
            .padding(.bottom, AngroveTheme.Spacing.illustratedCardPadding)
            .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
            .frame(maxWidth: .infinity)
        }
        .background(AngroveTheme.Colors.canvas)
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

/// A saved Worktree, styled like a Study Topic card: its name, what it holds, when it changed.
private struct WorktreeCard: View {
    let document: WorktreeDocument
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var summary: String {
        let windows = document.items.filter { $0.branches != nil }.count
        let count = document.items.count
        let items = windows > 0
            ? String(localized: "\(count) items, \(windows) conversations")
            : String(localized: "\(count) items")
        return items + " · " + String(localized: "Edited \(document.updatedAt.formatted(.relative(presentation: .named)))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: MacIcon.worktree.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    Text(document.displayTitle)
                        .font(.custom("Figtree-Bold", size: 18))
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                MacActionMenu(entries: { [
                    MacMenuEntry("Delete", symbol: "trash", destructive: true, action: onDelete)
                ] }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Board options")
            }
            Text(summary)
                .font(.custom("Figtree-Regular", size: 14))
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open"), onOpen)
    }
}
