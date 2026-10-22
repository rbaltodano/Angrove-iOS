import SwiftUI

struct MacFloatingSidebar: View {
    @Binding var selection: MacDestination
    var isCompact = false
    let showsFixture: Bool
    let conversations: [InquiryConversation]
    var loadingBranchIDs: Set<UUID> = []
    let openConversation: (UUID) -> Void
    let newConversation: () -> Void
    let openPreview: () -> Void
    let activeConversationID: UUID
    let openMenuID: UUID?
    let openMenu: (UUID) -> Void
    let renamingConversationID: UUID?
    let beginRename: (UUID) -> Void
    let finishRename: (UUID, String?) -> Void
    var menuAction: (MacSidebarConversationMenuAction, InquiryConversation) -> Void
    var openSearch: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var initializedPresentation = false
    @State private var compactVisible = false
    @State private var expandedPresented = true

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                MacCompactSidebar(selection: $selection,
                                  isPresented: initializedPresentation ? compactVisible : isCompact)
                    .frame(width: MacSidebarLayout.compactWidth)
                    .opacity((initializedPresentation ? compactVisible : isCompact) ? 1 : 0)
                    .allowsHitTesting(isCompact)
                    .accessibilityHidden(!isCompact)
                MacExpandedSidebar(selection: $selection, showsFixture: showsFixture,
                                   conversations: conversations, loadingBranchIDs: loadingBranchIDs, openConversation: openConversation,
                                   newConversation: newConversation, openPreview: openPreview,
                                   activeConversationID: activeConversationID, openMenuID: openMenuID, openMenu: openMenu,
                                   isPresented: initializedPresentation ? expandedPresented : !isCompact,
                                   renamingConversationID: renamingConversationID,
                                   beginRename: beginRename, finishRename: finishRename, menuAction: menuAction,
                                   openSearch: openSearch)
                    .frame(width: max(MacSidebarLayout.minimumWidth, geometry.size.width))
                    .opacity((initializedPresentation ? expandedPresented : !isCompact) ? 1 : 0)
                    .allowsHitTesting(!isCompact && expandedPresented)
                    .accessibilityHidden(isCompact || !expandedPresented)
            }
        }
        .frame(maxHeight: .infinity)
        .background(AngroveTheme.Colors.sideMenuSurface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(MacConversationStyle.border)
                .frame(width: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .task(id: isCompact) {
            if !initializedPresentation || reduceMotion {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    compactVisible = isCompact
                    expandedPresented = !isCompact
                    initializedPresentation = true
                }
                return
            }
            if isCompact {
                withAnimation(.easeOut(duration: MacSidebarTransition.fadeDuration)) { expandedPresented = false }
            }
            do { try await Task.sleep(for: .seconds(MacSidebarTransition.midpoint)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: MacSidebarTransition.fadeDuration)) { compactVisible = isCompact }
            if !isCompact {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { expandedPresented = true }
            }
        }
    }
}

private struct MacExpandedSidebar: View {
    private static let fixtureStudyTopics = [StudyTopic(title: "Summer Bible Study")]
    @State private var commandHeld = false
    @State private var hoveredDestination: MacDestination?
    @State private var savedStudyTopics = StudyTopicStore.load()
    @Binding var selection: MacDestination
    let showsFixture: Bool
    let conversations: [InquiryConversation]
    let loadingBranchIDs: Set<UUID>
    let openConversation: (UUID) -> Void
    let newConversation: () -> Void
    let openPreview: () -> Void
    let activeConversationID: UUID
    let openMenuID: UUID?
    let openMenu: (UUID) -> Void
    let isPresented: Bool
    let renamingConversationID: UUID?
    let beginRename: (UUID) -> Void
    let finishRename: (UUID, String?) -> Void
    var menuAction: (MacSidebarConversationMenuAction, InquiryConversation) -> Void
    let openSearch: () -> Void
    @State private var scrollEdges = Edges()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Reserves the pinned logo's space so the rows start beneath it.
                    logo.hidden()
                    SidebarSearchButton(showsShortcut: true, action: openSearch)
                        .help("Search (⌘K)")
                        .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.15, duration: 0.32, offset: 24))
                    navigation
                    ornament
                    if showsFixture || !savedStudyTopics.isEmpty {
                        studyTopics
                    }
                    recents
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MacSidebarLayout.contentInset)
                // Keep navigation below the window controls while its surface spans the window.
                .padding(.top, MacSidebarLayout.contentTopInset)
                // Let the last row scroll fully above the floating settings icon.
                .padding(.bottom, MacSidebarLayout.contentInset + Self.footerClearance)
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Edges.self) { geometry in
                let top = geometry.contentOffset.y + geometry.contentInsets.top > 0.5
                let bottom = geometry.contentOffset.y + geometry.containerSize.height
                    < geometry.contentSize.height - 0.5
                return Edges(top: top, bottom: bottom)
            } action: { _, edges in
                scrollEdges = edges
            }

            VStack(spacing: 0) {
                // Cover the window controls and pinned header instead of leaving a gap
                // above the gradient where scrolled rows would become visible again.
                AngroveTheme.Colors.sideMenuSurface.frame(height: 84)
                fade(from: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(scrollEdges.top ? 1 : 0)
            .animation(.easeInOut(duration: 0.14), value: scrollEdges.top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            fade(from: .bottom)
                .opacity(scrollEdges.bottom ? 1 : 0)
                .animation(.easeInOut(duration: 0.28), value: scrollEdges.bottom)
            logo
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.15, duration: 0.32, offset: 24))
                .padding(.horizontal, MacSidebarLayout.contentInset)
                .padding(.top, MacSidebarLayout.contentTopInset)
                .frame(maxHeight: .infinity, alignment: .top)
            footer
                .padding(.leading, MacSidebarLayout.contentInset)
                .padding(.bottom, MacSidebarLayout.contentInset)
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20))
        }
        .background(MacCommandKeyObserver { commandHeld = $0 })
        .onChange(of: isPresented) { _, isPresented in
            if !isPresented { hoveredDestination = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macConversationSaved)) { _ in
            savedStudyTopics = StudyTopicStore.load()
        }
    }

    private var logo: some View {
        Image("AngroveLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 150)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Angrove")
    }

    private var navigation: some View {
        // 44 pt rows 8 pt apart keep the Figma's 52 pt rhythm while the selection pill gets
        // the same 16 pt leading inset as the Study Topic and Recents rows.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MacDestination.sidebarDestinations) { destination in
                Button {
                    selection = destination
                } label: {
                    HStack(spacing: 16) {
                        MacIconView(icon: destination.asset)
                            .modifier(MacSidebarIconEntrance(isPresented: isPresented, delay: MacSidebarTransition.delay(for: destination)))
                        Text(destination.title)
                            .font(AngroveTheme.Typography.uiSubheading)
                            .foregroundStyle(AngroveTheme.Colors.paragraphText)
                            .modifier(MacSidebarEntrance(isPresented: isPresented,
                                delay: MacSidebarTransition.delay(for: destination) + 0.025))
                        if destination == .insights && showsFixture {
                            Text("1")
                                .font(AngroveTheme.Typography.uiLabel)
                                .foregroundStyle(AngroveTheme.Colors.canvasSecondary)
                                .frame(width: 18, height: 18)
                                .background(AngroveTheme.Colors.lightGreen, in: Capsule())
                                .padding(.leading, 8)
                                .modifier(MacSidebarEntrance(isPresented: isPresented,
                                    delay: MacSidebarTransition.delay(for: destination) + 0.025))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous)
                            .fill(selection.highlightsExpandedRow(destination) || hoveredDestination == destination
                                  ? AngroveTheme.Colors.sideMenuSelection : .clear)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                }
                .onHover { isHovered in
                    if isHovered { hoveredDestination = destination }
                    else if hoveredDestination == destination { hoveredDestination = nil }
                }
                .accessibilityAddTraits(selection.highlightsExpandedRow(destination) ? .isSelected : [])
            }
        }
    }

    private var ornament: some View {
        MacSidebarEntranceDivider(isPresented: isPresented)
    }

    private var studyTopics: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacPageHeading(title: "Study Topics")
                .frame(height: 27)
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.15, duration: 0.32, offset: 24))
            ForEach(showsFixture ? Self.fixtureStudyTopics : savedStudyTopics) { topic in
                Button { selection = .studyTopics } label: {
                    HStack(spacing: 10) {
                        MacIconView(icon: .studyTopic)
                        Text(MacStudyTopicsView.displayTitle(topic))
                            .font(AngroveTheme.Typography.body)
                            .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20))
            }
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                MacPageHeading(title: "Recents")
                Spacer(minLength: 8)
                Button(action: newConversation) {
                    Image(systemName: MacIcon.plus.symbol)
                        .font(.system(size: MacIcon.plus.size, weight: .medium))
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .frame(width: 28, height: 27)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("New Conversation")
                .help("New Conversation (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
            .frame(height: 27)
            .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.15, duration: 0.32, offset: 24))
            #if DEBUG
            if showsFixture {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button("What is the Didache?", action: openPreview)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MacActionMenu(entries: { [MacMenuEntry("Open design preview", symbol: "eye", action: openPreview)] }) {
                            MacIconView(icon: .ellipsis)
                                .frame(width: 24, height: 28)
                        }
                        .accessibilityLabel("Conversation options")
                        .fixedSize()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(AngroveTheme.Colors.sideMenuSelection, in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous))
                    Button("How Much Does Intention Matter?", action: openPreview)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                    Button("What Makes an Action Right or Wrong?", action: openPreview)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                }
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20))
            } else {
                savedConversations
            }
            #else
            savedConversations
            #endif
        }
    }

    private var savedConversations: some View {
        VStack(alignment: .leading, spacing: 4) {
            if conversations.isEmpty {
                Text("No conversations yet").foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20))
            }
            ForEach(Array(MacSidebarConversationActions.sorted(conversations).enumerated()), id: \.element.id) { index, conversation in
                MacSidebarConversationRow(conversation: conversation,
                    isSelected: selection == .conversations && activeConversationID == conversation.id,
                    isMenuOpen: openMenuID == conversation.id,
                    shortcutNumber: index < 9 ? index + 1 : nil,
                    showsShortcut: commandHeld && isPresented,
                    isLoading: !loadingBranchIDs.isDisjoint(with: conversation.branches.map(\.id)),
                    onOpen: { openConversation(conversation.id) }, onMenu: { openMenu(conversation.id) },
                    isRenaming: renamingConversationID == conversation.id,
                    onRename: { beginRename(conversation.id) },
                    onFinishRename: { finishRename(conversation.id, $0) },
                    contextEntries: { isPresented ? MacSidebarConversationMenu.entries(for: conversation) { menuAction($0, conversation) } : [] })
                    .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20 + Double(index) * 0.05))
                    // Drag a conversation onto a Worktree to place it there.
                    .draggable(WorktreeConversationDrop.payload(conversation.id)) {
                        MacConversationChip(title: conversation.title)
                    }
            }
        }.font(AngroveTheme.Typography.body).foregroundStyle(AngroveTheme.Colors.paragraphText)
    }

    private static let footerClearance: CGFloat = 64

    private struct Edges: Equatable { var top = false, bottom = false }

    private func fade(from edge: VerticalEdge) -> some View {
        let surface = AngroveTheme.Colors.sideMenuSurface
        return LinearGradient(colors: [surface, surface.opacity(0)],
                              startPoint: edge == .top ? .top : .bottom,
                              endPoint: edge == .top ? .bottom : .top)
            .frame(height: 120)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button { selection = .settings } label: {
                MacIconView(icon: .settings)
                    .background {
                        RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous)
                            .fill(selection == .settings || hoveredDestination == .settings
                                  ? AngroveTheme.Colors.sideMenuSelection : .clear)
                            .padding(-12)
                            .allowsHitTesting(false)
                    }
                    .frame(width: 44, height: MacIcon.settings.size, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .onHover { isHovered in
                if isHovered { hoveredDestination = .settings }
                else if hoveredDestination == .settings { hoveredDestination = nil }
            }
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(selection == .settings ? .isSelected : [])
        }
    }
}

private struct MacCompactSidebar: View {
    @Binding var selection: MacDestination
    let isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            AppIconImage(size: 32)
                .frame(width: 44, height: 44)
                .padding(.bottom, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Angrove")
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0, duration: 0.20, offset: 0))
            ForEach(Array(MacDestination.sidebarDestinations.enumerated()), id: \.element.id) { index, destination in
                MacCompactSidebarButton(destination: destination, isSelected: selection.highlights(destination),
                                        onSelect: { selection = destination })
                    .modifier(MacSidebarEntrance(isPresented: isPresented,
                        delay: Double(index + 1) * 0.06, duration: 0.20, offset: 0))
            }
            Spacer(minLength: 0)
            MacCompactSidebarButton(destination: .settings, isSelected: selection == .settings,
                                    onSelect: { selection = .settings })
                .padding(.bottom, MacSidebarLayout.contentInset)
        }
        .frame(width: 44)
        .padding(.top, MacSidebarLayout.contentTopInset)
        .padding(.horizontal, MacSidebarLayout.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
