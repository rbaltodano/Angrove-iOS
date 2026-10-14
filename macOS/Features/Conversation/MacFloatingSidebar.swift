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
                                   isPresented: initializedPresentation ? expandedPresented : !isCompact)
                    .frame(width: max(MacSidebarLayout.minimumWidth, geometry.size.width))
                    .opacity((initializedPresentation ? expandedPresented : !isCompact) ? 1 : 0)
                    .allowsHitTesting(!isCompact && expandedPresented)
                    .accessibilityHidden(isCompact || !expandedPresented)
            }
        }
        .frame(maxHeight: .infinity)
        .background(AngroveTheme.Colors.chipFill)
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

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    studying
                        .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.15, duration: 0.32, offset: 24))
                    navigation
                    ornament
                    studyTopics
                    recents
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            footer
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20))
        }
        .padding(MacSidebarLayout.contentInset)
        // Keep navigation below the window controls while its surface spans the window.
        .padding(.top, MacSidebarLayout.contentTopInset - MacSidebarLayout.contentInset)
    }

    private var studying: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENTLY STUDYING")
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .frame(height: 18)
            Text(showsFixture ? "What is The Didache?" : "A New Conversation")
                .font(BrandTypography.font("LibreBaskerville-Regular", size: 28))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(MacDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    HStack(spacing: 16) {
                        MacIconView(icon: destination.asset)
                            .modifier(MacSidebarIconEntrance(isPresented: isPresented, delay: MacSidebarTransition.delay(for: destination)))
                        Text(destination.title)
                            .font(MacConversationStyle.serifBody)
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
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(selection == destination ? .isSelected : [])
            }
        }
    }

    private var ornament: some View {
        MacSidebarEntranceDivider(isPresented: isPresented)
    }

    private var studyTopics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Study Topics")
                .font(AngroveTheme.Typography.uiHeading)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .frame(height: 27)
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.15, duration: 0.32, offset: 24))
            if showsFixture {
                Button { selection = .studyTopics } label: {
                    HStack(spacing: 10) {
                        MacIconView(icon: .studyTopic)
                        Text("Summer Bible Study")
                            .font(AngroveTheme.Typography.body)
                            .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20))
            } else {
                Text("No study topics yet")
                    .font(AngroveTheme.Typography.body)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .frame(height: 44)
                    .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20))
            }
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recents")
                .font(AngroveTheme.Typography.uiHeading)
                .foregroundStyle(AngroveTheme.Colors.headingText)
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
                        Menu {
                            Button("Open design preview", action: openPreview)
                        } label: {
                            MacIconView(icon: .ellipsis)
                                .frame(width: 24, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Conversation options")
                        .fixedSize()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(AngroveTheme.Colors.systemSelection, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    isLoading: !loadingBranchIDs.isDisjoint(with: conversation.branches.map(\.id)),
                    onOpen: { openConversation(conversation.id) }, onMenu: { openMenu(conversation.id) })
                    .modifier(MacSidebarEntrance(isPresented: isPresented, delay: 0.20 + Double(index) * 0.05))
            }
        }.font(AngroveTheme.Typography.body).foregroundStyle(AngroveTheme.Colors.paragraphText)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            SettingsLink {
                MacIconView(icon: .settings)
                    .frame(width: 44, height: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            Spacer(minLength: 8)
            Button(action: newConversation) {
                HStack(spacing: 8) {
                    MacIconView(icon: .plus)
                    Text("New Conversation")
                        .font(AngroveTheme.Typography.body)
                        .foregroundStyle(AngroveTheme.Colors.canvas)
                        .lineLimit(1)
                }
                .frame(width: 175, height: 52)
                .background(AngroveTheme.Colors.lightGreen, in: Capsule())
                .contentShape(Capsule())
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .background(AngroveTheme.Colors.chipFill)
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
            ForEach(Array(MacDestination.allCases.enumerated()), id: \.element.id) { index, destination in
                MacCompactSidebarButton(destination: destination, isSelected: selection == destination,
                                        onSelect: { selection = destination })
                    .modifier(MacSidebarEntrance(isPresented: isPresented,
                        delay: Double(index + 1) * 0.06, duration: 0.20, offset: 0))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 44)
        .padding(.top, MacSidebarLayout.contentTopInset)
        .padding(.horizontal, MacSidebarLayout.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
