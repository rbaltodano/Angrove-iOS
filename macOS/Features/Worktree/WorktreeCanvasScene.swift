import AppKit
import QuartzCore
import SwiftUI

/// Camera updates have a separate bridge: they never replace the scene's SwiftUI content.
@MainActor final class WorktreeSceneBridge {
    weak var view: WorktreeSceneView?
    var camera = CanvasScrollTransform(scale: 1, offset: .zero)
    var viewport = CGSize.zero

    func move(_ camera: CanvasScrollTransform, viewport: CGSize) {
        self.camera = camera
        self.viewport = viewport
        view?.move(camera, viewport: viewport)
    }
}

struct WorktreeSceneCameraDriver: NSViewRepresentable {
    let bridge: WorktreeSceneBridge
    let camera: CanvasScrollTransform
    let viewport: CGSize
    func makeNSView(context: Context) -> WorktreeScenePassThrough { WorktreeScenePassThrough() }
    func updateNSView(_ view: WorktreeScenePassThrough, context: Context) { bridge.move(camera, viewport: viewport) }
}

final class WorktreeScenePassThrough: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Observation of content stays here, away from the frequently changing camera.
struct WorktreeSceneContent: View, Equatable {
    let board: WorktreeBoard
    let runtime: MacApplicationRuntime
    let pointer: WorktreeCanvasPointer
    let bridge: WorktreeSceneBridge
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var responseSize: ConversationFontSizeOption = .medium

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.board === rhs.board && lhs.runtime === rhs.runtime && lhs.pointer === rhs.pointer && lhs.bridge === rhs.bridge }
    }

    var body: some View {
        let entries = board.items.map { item in
            WorktreeSceneEntry(item: item, branches: item.session?.branches,
                savedIDs: item.session?.savedIDs ?? [], isSavedInsight: item.insight.map { board.savedInsightIDs.contains($0.id) } ?? false,
                needsLiveContent: item.isSummarizing || item.revealsSummary || item.labelWork != nil || item.outputWork != nil
                    || ["\"", "“"].contains(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    || item.arrivalTitle != nil || item.session?.isComposerReady == false || item.session?.pendingResponses.isEmpty == false,
                isEditing: board.editingID.map { [item.id, item.labelID, item.followUpID].contains($0) } ?? false,
                isSelected: board.selection.contains(item.id))
        }
        WorktreeNativeScene(board: board, runtime: runtime, pointer: pointer, bridge: bridge,
            entries: entries, typography: "\(responseFont.rawValue)-\(responseSize.rawValue)")
    }
}

struct WorktreeSceneEntry: Equatable {
    let item: WorktreeBoard.Item
    let branches: [ChatBranch]?
    let savedIDs: Set<UUID>
    let isSavedInsight: Bool
    let needsLiveContent: Bool
    let isEditing: Bool
    let isSelected: Bool

    /// A camera-independent item position does not change the rendered content.
    func hasSameContent(as other: Self) -> Bool {
        var placedItem = item
        placedItem.origin = other.item.origin
        return placedItem == other.item && branches == other.branches && savedIDs == other.savedIDs
            && isSavedInsight == other.isSavedInsight && needsLiveContent == other.needsLiveContent
            && isEditing == other.isEditing && isSelected == other.isSelected
    }
}

private struct WorktreeNativeScene: NSViewRepresentable {
    let board: WorktreeBoard
    let runtime: MacApplicationRuntime
    let pointer: WorktreeCanvasPointer
    let bridge: WorktreeSceneBridge
    let entries: [WorktreeSceneEntry]
    let typography: String

    func makeNSView(context: Context) -> WorktreeSceneView {
        let view = WorktreeSceneView(board: board, runtime: runtime, pointer: pointer)
        bridge.view = view
        view.move(bridge.camera, viewport: bridge.viewport)
        return view
    }
    func updateNSView(_ view: WorktreeSceneView, context: Context) {
        view.update(entries, environment: context.environment, typography: typography)
    }
    static func dismantleNSView(_ view: WorktreeSceneView, coordinator: ()) { view.stop() }
}

/// A retained native scene. Inactive nodes are CGImage layers; live hosts are attached only
/// for interaction, animation, or generation. One bounds transform moves the entire world.
@MainActor final class WorktreeSceneView: NSView {
    private final class World: NSView {
        override var isFlipped: Bool { true }
    }
    private final class DragReceiver: NSView {
        weak var scene: WorktreeSceneView?
        var itemID: UUID?
        var resizeHandle: WorktreePhotoHandle?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { itemID == nil ? nil : self }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let itemID else { return }
            if let resizeHandle { scene?.beginResize(itemID, handle: resizeHandle, event: event) }
            else { scene?.beginDrag(itemID, event: event) }
        }
        override func mouseDragged(with event: NSEvent) {
            if scene?.itemResize != nil { scene?.resize(event) } else { scene?.drag(event) }
        }
        override func mouseUp(with event: NSEvent) {
            if scene?.itemResize != nil { scene?.endResize() } else { scene?.endDrag() }
            itemID = nil
            resizeHandle = nil
        }
    }
    private struct ItemDrag {
        let id: UUID
        let origin: CGPoint
        let start: CGPoint
        let scale: CGFloat
        var moved = false
    }
    private struct ItemResize {
        let item: WorktreeBoard.Item
        let size: CGSize
        let start: CGPoint
        let handle: WorktreePhotoHandle
        let scale: CGFloat
    }
    private final class Surface: NSView {
        var accessibilityActivation: (() -> Bool)?
        override var isFlipped: Bool { true }
        override func accessibilityPerformPress() -> Bool { accessibilityActivation?() ?? false }
    }
    @MainActor private final class Node {
        var entry: WorktreeSceneEntry
        let surface = Surface()
        let image = CALayer()
        let host: WorktreeNodeHostingView
        var dirty = true
        var byteCount = 0
        var snapshot: CGImage?
        var resolution: CGFloat = 0
        var renderedScale: CGFloat = 1
        var lastUse: UInt64 = 0
        var measured = false
        var canCache = true
        var sizeDirty = true
        var preferredSize: CGSize?
        var interactionDirty = false
        var hasAppeared = false
        var isScrolling = false
        let scrollActivity = WorktreeConversationScrollActivity()
        var scrollSettle: DispatchWorkItem?
        weak var observedClip: NSClipView?
        var scrollObserver: NSObjectProtocol?
        var observedOffset = CGPoint.zero
        var captureAfter: CFTimeInterval = 0
        var presentation: DispatchWorkItem?
        var isStagingCache = false
        var isCapturing = false
        var snapshotPreparedAt: CFTimeInterval?
        var cacheAfter: CFTimeInterval
        static func revealDelay(_ item: WorktreeBoard.Item) -> Double {
            let words = max(item.label?.split(separator: " ").count ?? 0,
                            item.isHeading ? item.text.split(separator: " ").count : 0)
            return max(1, 0.8 + Double(max(0, words - 1)) * 0.055)
        }
        init(entry: WorktreeSceneEntry, root: AnyView) {
            self.entry = entry
            cacheAfter = CACurrentMediaTime() + Self.revealDelay(entry.item)
            host = WorktreeNodeHostingView(rootView: root)
            host.sizingOptions = [.intrinsicContentSize]
            host.safeAreaRegions = []
            surface.wantsLayer = true
            surface.layer?.addSublayer(image)
        }
    }
    private let board: WorktreeBoard
    private let runtime: MacApplicationRuntime
    private let pointer: WorktreeCanvasPointer
    private let world = World()
    private let dragReceiver = DragReceiver()
    private var itemDrag: ItemDrag?
    private var itemResize: ItemResize?
    private var dragPreparation: DispatchWorkItem?
    private var dragImageIDs: Set<UUID> = []
    private var nodes: [UUID: Node] = [:]
    private var orderedIDs: [UUID] = []
    private var environment: EnvironmentValues?
    private var renderedScheme: ColorScheme?
    private var typography = ""
    private var camera = CanvasScrollTransform(scale: 1, offset: .zero)
    private var settle: DispatchWorkItem?
    private var refresh: DispatchWorkItem?
    private var positionSettle: DispatchWorkItem?
    private var movingIDs: Set<UUID> = []
    private var interactingID: UUID?
    private var pointerArea: NSTrackingArea?
    private var pointerLocation: CGPoint?
    private var pointerObservers: [NSObjectProtocol] = []
    private var isStopped = false
    private var hoveredID: UUID?
    private var isOverNativeGrip = false
    private var counter: UInt64 = 0
    private var builds = 0
    private var isMoving = false
    // A card shifts its chrome up by 28pt; its label extends another 50pt above that.
    // The bitmap must include the complete label and glyph ascenders, not just the card.
    private static let inset: CGFloat = 96
    private static let budget = 128 * 1024 * 1024

    override var isFlipped: Bool { true }
    init(board: WorktreeBoard, runtime: MacApplicationRuntime, pointer: WorktreeCanvasPointer) {
        self.board = board
        self.runtime = runtime
        self.pointer = pointer
        super.init(frame: .zero)
        wantsLayer = true
        autoresizesSubviews = false
        clipsToBounds = true
        world.wantsLayer = true
        world.autoresizesSubviews = false
        world.clipsToBounds = false
        addSubview(world)
        dragReceiver.scene = self
        addSubview(dragReceiver)

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        pointerArea = nil
        guard window != nil, !isStopped else { return }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in pointerObservers { NotificationCenter.default.removeObserver(observer) }
        pointerObservers = []
        clearPointer()
        guard let window, !isStopped else { return }
        window.acceptsMouseMovedEvents = true
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                               (NSApplication.didResignActiveNotification, NSApp as AnyObject)] {
            pointerObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clearPointer() }
            })
        }
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseMoved(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { clearPointer() }

    private func trackPointer(_ event: NSEvent) {
        guard event.window === window, !isStopped else { clearPointer(); return }
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location), visibleRect.contains(location) else { clearPointer(); return }
        pointerLocation = location
        refreshPointer()
    }

    private func refreshPointer() {
        let location = pointerLocation.map { world.convert($0, from: self) }
        pointer.update(world: location, board: board, zoom: camera.scale)
        hover(world: location)
    }

    private func clearPointer() {
        pointerLocation = nil
        pointer.update(world: nil, board: board, zoom: camera.scale)
        releaseHoverInteraction()
        hover(world: nil)
        if let previous = hoveredID { board.setHovered(previous, false) }
        hoveredID = nil
    }

    func update(_ entries: [WorktreeSceneEntry], environment: EnvironmentValues, typography: String) {
        let restyle = renderedScheme != environment.colorScheme || self.typography != typography
        self.environment = environment
        renderedScheme = environment.colorScheme
        self.typography = typography
        let ids = Set(entries.map { $0.item.id })
        for id in Array(nodes.keys) where !ids.contains(id) {
            movingIDs.remove(id)
            if let removed = nodes.removeValue(forKey: id) {
                removed.presentation?.cancel()
                removed.scrollSettle?.cancel()
                if let observer = removed.scrollObserver { NotificationCenter.default.removeObserver(observer) }
                removed.host.removeFromSuperview()
                removed.surface.removeFromSuperview()
            }
        }
        orderedIDs = entries.sorted { !$0.isSelected && $1.isSelected }.map { $0.item.id }
        for entry in entries {
            let node: Node
            if let existing = nodes[entry.item.id] {
                node = existing
                let moved = node.entry.item.origin != entry.item.origin
                let contentChanged = !node.entry.hasSameContent(as: entry) || restyle
                if moved {
                    movingIDs.insert(entry.item.id)
                    settlePositions()
                }
                if contentChanged {
                    if node.entry.item.labelRevision != entry.item.labelRevision || node.entry.item.isHeading != entry.item.isHeading
                        || (entry.item.isHeading && node.entry.item.text != entry.item.text) {
                        node.cacheAfter = CACurrentMediaTime() + Node.revealDelay(entry.item)
                    }
                    node.entry = entry
                    node.host.rootView = root(for: node, environment: environment)
                    node.dirty = true
                } else {
                    // Retain the latest model position without replacing the SwiftUI root or bitmap.
                    node.entry = entry
                }
            } else {
                node = Node(entry: entry, root: AnyView(EmptyView()))
                nodes[entry.item.id] = node
                node.renderedScale = camera.scale
                node.scrollActivity.onScroll = { [weak self, weak node] in
                    guard let self, let node else { return }
                    node.isScrolling = true
                    node.scrollSettle?.cancel()
                    let work = DispatchWorkItem { [weak self, weak node] in
                        guard let self, let node else { return }
                        node.isScrolling = false
                        node.captureAfter = CACurrentMediaTime() + 0.05
                        node.dirty = true
                        self.scheduleRefresh()
                    }
                    node.scrollSettle = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
                }
                node.surface.accessibilityActivation = { [weak self, weak node] in
                    guard let self, let node else { return false }
                    self.interactingID = node.entry.item.id
                    self.activate(node)
                    node.host.layoutSubtreeIfNeeded()
                    NSAccessibility.post(element: node.host, notification: .layoutChanged)
                    return true
                }
                node.host.onSizeChange = { [weak self, weak node] in
                    guard let self, let node, node.host.superview != nil, !node.isCapturing else { return }
                    node.sizeDirty = true
                    self.scheduleRefresh()
                }
                world.addSubview(node.surface)
                node.surface.setFrameSize(CGSize(width: (entry.item.size?.width ?? 480) + Self.inset * 2,
                                                height: (entry.item.size?.height ?? 160) + Self.inset * 2))
                node.host.rootView = root(for: node, environment: environment)
                activate(node)
            }
            position(node)
            if node.host.superview != nil { positionLive(node) }
            node.surface.setAccessibilityRole(.button)
            node.surface.setAccessibilityLabel(entry.item.label ?? entry.item.insight?.word
                ?? entry.item.session?.activeBranch?.topQuestionText ?? entry.item.text)
            node.surface.setAccessibilityHelp("Interact with this item")
            if entry.needsLiveContent || entry.isEditing { activate(node) }
        }
        // Layer ordering and hit ordering use the same stable item sequence.
        for (index, id) in orderedIDs.enumerated() {
            nodes[id]?.surface.layer?.zPosition = CGFloat(index)
        }
        scheduleRefresh()
    }

    private func settlePositions() {
        positionSettle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let environment = self.environment else { return }
            let ids = self.movingIDs.filter { $0 != self.itemDrag?.id }
            self.movingIDs.subtract(ids)
            for id in ids {
                guard let node = self.nodes[id] else { continue }
                // Synchronize the gesture's next starting origin once movement ends.
                node.host.rootView = self.root(for: node, environment: environment)
                node.host.alphaValue = 1
                self.positionLive(node)
                node.image.isHidden = node.host.superview != nil
                node.dirty = true
            }
            self.scheduleRefresh()
        }
        positionSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func root(for node: Node, environment: EnvironmentValues, capturesSnapshot: Bool = false) -> AnyView {
        let entry = node.entry
        let labelWidth = entry.item.label.map {
            ($0 as NSString).size(withAttributes: [.font: NSFont(name: "LibreBaskerville-Regular", size: 28) ?? .systemFont(ofSize: 28)]).width
        } ?? 0
        let scale = camera.scale
        let size = node.surface.bounds.size
        return AnyView(WorktreeItemView(board: board, item: entry.item, scale: scale, runtime: runtime, pointer: pointer)
            .equatable().fixedSize().padding(Self.inset)
            .frame(minWidth: min(labelWidth, 640) + Self.inset * 2, alignment: .topLeading)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self, weak node] size in
                guard let self, let node, size.width > 0, size.height > 0, node.preferredSize != size else { return }
                node.preferredSize = size
                node.sizeDirty = true
                self.scheduleRefresh()
            }
            .onAppear { [weak node] in
                guard let node, !node.hasAppeared else { return }
                node.hasAppeared = true
                // Appearance can lag creation while other cards finish their first layout.
                node.cacheAfter = max(node.cacheAfter, CACurrentMediaTime() + Node.revealDelay(node.entry.item))
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .environment(\.self, environment)
            .environment(\.worktreeConversationScrollActivity, node.scrollActivity)
            .environment(\.worktreeCapturesSnapshot, capturesSnapshot || node.snapshotPreparedAt != nil))
    }

    private func positionLive(_ node: Node) {
        let frame = CGRect(x: bounds.width / 2 + camera.offset.width + node.surface.frame.minX * camera.scale,
                                 y: bounds.height / 2 + camera.offset.height + node.surface.frame.minY * camera.scale,
                                 width: node.surface.bounds.width * camera.scale, height: node.surface.bounds.height * camera.scale)
        if node.host.frame != frame { node.host.frame = frame }
        node.host.layer?.zPosition = CGFloat((orderedIDs.firstIndex(of: node.entry.item.id) ?? 0) + 1)
    }

    private func position(_ node: Node) {
        node.surface.setFrameOrigin(CGPoint(x: node.entry.item.origin.x - Self.inset,
                                           y: node.entry.item.origin.y - Self.inset))
    }

    func move(_ camera: CanvasScrollTransform, viewport: CGSize) {
        let changed = self.camera.scale != camera.scale || self.camera.offset != camera.offset
        self.camera = camera
        guard viewport.width > 0, viewport.height > 0 else { return }
        if changed {
            interactingID = nil
            if !isMoving {
                for node in nodes.values where node.host.superview != nil && node.interactionDirty && !node.entry.needsLiveContent && !node.entry.isEditing && !node.isScrolling {
                    node.host.layoutSubtreeIfNeeded()
                    _ = capture(node, resolution: max(0.25, node.resolution))
                }
            }
            isMoving = true
            for node in nodes.values where !node.entry.needsLiveContent && !node.entry.isEditing && !node.isScrolling
                && (CACurrentMediaTime() >= node.captureAfter || node.snapshotPreparedAt != nil)
                && !node.dirty && node.image.contents != nil {
                // A gesture never replaces content with an empty or stale cache.
                node.host.removeFromSuperview()
                if interactingID == node.entry.item.id { interactingID = nil }
                node.surface.setAccessibilityElement(true)
                node.image.isHidden = false
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dragReceiver.frame = CGRect(origin: .zero, size: viewport)
        world.frame = CGRect(origin: .zero, size: viewport)
        world.bounds = CGRect(x: (-viewport.width / 2 - camera.offset.width) / camera.scale,
                              y: (-viewport.height / 2 - camera.offset.height) / camera.scale,
                              width: viewport.width / camera.scale, height: viewport.height / camera.scale)
        updateVisibility()
        for node in nodes.values where node.host.superview != nil {
            if node.renderedScale != camera.scale, let environment {
                node.host.rootView = root(for: node, environment: environment)
                node.renderedScale = camera.scale
            }
            positionLive(node)
        }
        CATransaction.commit()
        // A stationary screen pointer changes world position as the camera moves.
        if pointerLocation != nil { refreshPointer() }
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isMoving = false
            if self.pointerLocation != nil { self.refreshPointer() }
            self.scheduleRefresh()
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func updateVisibility() {
        let visible = world.bounds.insetBy(dx: -120 / camera.scale, dy: -120 / camera.scale)
        for node in nodes.values {
            node.surface.isHidden = node.measured && !node.surface.frame.intersects(visible)
                && !node.entry.needsLiveContent && !node.entry.isEditing && !node.isScrolling
            if node.surface.isHidden && !node.entry.needsLiveContent && !node.entry.isEditing && !node.isScrolling {
                node.host.removeFromSuperview()
                if interactingID == node.entry.item.id { interactingID = nil }
            }
            if !node.surface.isHidden && node.image.contents == nil && node.host.superview == nil { activate(node) }
        }
    }

    private func activate(_ node: Node, forCache: Bool = false) {
        if !forCache, node.snapshotPreparedAt != nil {
            node.snapshotPreparedAt = nil
            if let environment { node.host.rootView = root(for: node, environment: environment) }
        }
        node.surface.setAccessibilityElement(false)
        if node.renderedScale != camera.scale, let environment {
            node.host.rootView = root(for: node, environment: environment)
            node.renderedScale = camera.scale
            node.dirty = true
        }
        counter += 1
        node.lastUse = counter
        let attached = node.host.superview != nil
        let stage = forCache && node.snapshot != nil && (!attached || node.isStagingCache)
        node.surface.setAccessibilityElement(stage)
        if !attached {
            node.captureAfter = CACurrentMediaTime() + 0.05
            node.isStagingCache = stage
            node.host.alphaValue = stage ? 0 : 1
            addSubview(node.host)
        }
        if stage {
            // Resolution work must not briefly expose a newly mounted lazy transcript.
            // Its previous image stays visible while the native host lays out offscreen.
            node.presentation?.cancel()
            node.presentation = nil
            node.image.isHidden = false
        } else if !attached || node.isStagingCache {
            node.isStagingCache = false
            node.host.alphaValue = 1
            node.presentation?.cancel()
            let work = DispatchWorkItem { [weak self, weak node] in
                guard let self, let node else { return }
                node.presentation = nil
                guard node.host.superview === self, !node.isStagingCache else { return }
                node.host.layoutSubtreeIfNeeded()
                node.host.displayIfNeeded()
                self.observeScroll(node)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                node.image.isHidden = true
                CATransaction.commit()
            }
            node.presentation = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
        } else if node.presentation == nil { node.image.isHidden = true }
        positionLive(node)
        node.interactionDirty = true
    }

    private func presentCache(_ node: Node) {
        node.presentation?.cancel()
        node.presentation = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        node.image.isHidden = false
        node.host.removeFromSuperview()
        node.isStagingCache = false
        node.host.alphaValue = 1
        node.surface.setAccessibilityElement(true)
        CATransaction.commit()
    }

    private func observeScroll(_ node: Node) {
        guard node.entry.item.isQuestion else { return }
        if let clip = node.observedClip, clip.isDescendant(of: node.host) { return }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        guard let clip = findScroll(node.host)?.contentView else { return }
        if let observer = node.scrollObserver { NotificationCenter.default.removeObserver(observer) }
        node.observedClip = clip
        node.observedOffset = clip.bounds.origin
        clip.postsBoundsChangedNotifications = true
        node.scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: clip, queue: .main) { [weak node] _ in
                MainActor.assumeIsolated {
                    guard let node, let clip = node.observedClip else { return }
                    let offset = clip.bounds.origin
                    guard offset != node.observedOffset else { return }
                    node.observedOffset = offset
                    node.scrollActivity.onScroll?()
                }
            }
    }

    private func scheduleRefresh() {
        guard refresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refresh = nil
            self.refreshNext()
        }
        refresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
    }

    private func refreshNext() {
        guard !isMoving, let environment else { return }
        updateVisibility()
        let visibleNodes = orderedIDs.compactMap { nodes[$0] }.filter { !$0.surface.isHidden }
        let area = visibleNodes.reduce(CGFloat.zero) { $0 + max(1, $1.surface.bounds.width * $1.surface.bounds.height) }
        let budgetScale = sqrt(CGFloat(Self.budget) * 0.9 / max(1, area * 4))
        let resolution = min(budgetScale, displayResolution)
        // One surface per run-loop turn, so building caches cannot block all interactions.
        let now = CACurrentMediaTime()
        guard let node = visibleNodes.first(where: {
            !movingIDs.contains($0.entry.item.id) && !dragImageIDs.contains($0.entry.item.id) && ($0.sizeDirty || (!$0.measured || $0.dirty) && ($0.entry.needsLiveContent || $0.entry.isEditing || !$0.measured)
                || ($0.canCache && interactingID != $0.entry.item.id && !$0.isScrolling && !$0.entry.needsLiveContent && !$0.entry.isEditing && now >= $0.cacheAfter
                    && ($0.dirty || $0.snapshotPreparedAt != nil || abs($0.resolution - resolution) > 0.25)))
        }) else {
            if visibleNodes.contains(where: { !dragImageIDs.contains($0.entry.item.id) && $0.canCache && $0.dirty && interactingID != $0.entry.item.id && !$0.isScrolling && !$0.entry.needsLiveContent && !$0.entry.isEditing }) { scheduleRefresh() }
            return
        }
        if node.dirty { node.host.rootView = root(for: node, environment: environment) }
        activate(node, forCache: true)
        node.host.layoutSubtreeIfNeeded()
        let size = node.preferredSize ?? node.surface.bounds.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        if node.surface.frame.size != size {
            node.surface.setFrameSize(size)
            node.host.rootView = root(for: node, environment: environment)
        }
        positionLive(node)
        node.host.layoutSubtreeIfNeeded()
        observeScroll(node)
        node.sizeDirty = node.preferredSize.map { $0 != node.surface.bounds.size } ?? false
        if node.sizeDirty {
            node.dirty = true
            scheduleRefresh()
            return
        }
        node.measured = true
        if node.entry.needsLiveContent || node.entry.isEditing || node.isScrolling || interactingID == node.entry.item.id {
            if node.isStagingCache { activate(node) }
            node.dirty = false
            scheduleRefresh()
            return
        }
        if now < max(node.cacheAfter, node.captureAfter) {
            node.dirty = true
            scheduleRefresh()
            return
        }
        // Very large native documents stay live rather than allocating an unbounded bitmap.
        if node.host.bounds.width * node.host.bounds.height * pow(window?.backingScaleFactor ?? 2, 2) > 16_000_000 {
            node.canCache = false
            if node.isStagingCache { activate(node) }
            node.dirty = false
            scheduleRefresh()
            return
        }
        if capture(node, resolution: resolution) {
            if interactingID != node.entry.item.id {
                presentCache(node)
            } else { node.image.isHidden = true }
        }
        enforceBudget()
        scheduleRefresh()
    }

    private func prepareSnapshot(_ node: Node) {
        guard node.snapshotPreparedAt == nil, let environment else { return }
        node.snapshotPreparedAt = CACurrentMediaTime()
        node.host.rootView = root(for: node, environment: environment, capturesSnapshot: true)
        node.host.layoutSubtreeIfNeeded()
        // SwiftUI/CALayer display updates are deferred even after layout. Do not take the
        // bitmap in this same run-loop turn, or it can retain the previously lit chrome.
        node.captureAfter = max(node.captureAfter, CACurrentMediaTime() + 0.032)
    }

    @discardableResult private func capture(_ node: Node, resolution: CGFloat) -> Bool {
        let size = node.surface.bounds.size
        guard !node.isScrolling else { return false }
        if node.snapshotPreparedAt == nil {
            prepareSnapshot(node)
            scheduleRefresh()
            return false
        }
        guard CACurrentMediaTime() >= node.captureAfter,
              size.width > 0, size.height > 0,
              size.width * size.height * resolution * resolution <= 16_000_000,
              node.host.bounds.width * node.host.bounds.height * pow(window?.backingScaleFactor ?? 2, 2) <= 16_000_000,
              let bitmap = node.host.bitmapImageRepForCachingDisplay(in: node.host.bounds) else { return false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let originalAlpha = node.host.alphaValue
        node.isCapturing = true
        node.host.alphaValue = 1
        node.host.layoutSubtreeIfNeeded()
        defer {
            node.snapshotPreparedAt = nil
            if let environment { node.host.rootView = root(for: node, environment: environment) }
            node.host.layoutSubtreeIfNeeded()
            node.isCapturing = false
            node.host.alphaValue = originalAlpha
            CATransaction.commit()
        }
        node.host.displayIfNeeded()
        node.host.cacheDisplay(in: node.host.bounds, to: bitmap)
        guard !node.isScrolling else { return false }
        guard let source = bitmap.cgImage,
              let context = CGContext(data: nil, width: max(1, Int(ceil(size.width * resolution))),
                height: max(1, Int(ceil(size.height * resolution))), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let image = context.makeImage() else { return false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if node.isStagingCache, node.snapshot != nil, !node.image.isHidden,
           environment?.accessibilityReduceMotion != true {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.1
            node.image.add(fade, forKey: "resolutionUpgrade")
        }
        node.image.contents = image
        node.snapshot = image
        builds += 1
        node.image.frame = node.surface.bounds
        node.image.contentsScale = resolution
        node.image.isHidden = node.host.superview != nil && !node.isStagingCache
        CATransaction.commit()
        node.byteCount = image.bytesPerRow * image.height
        node.resolution = resolution
        node.dirty = false
        node.interactionDirty = false
        node.measured = true
        return true
    }

    private func enforceBudget() {
        var bytes = nodes.values.reduce(0) { $0 + $1.byteCount }
        for node in nodes.values.sorted(by: { $0.lastUse < $1.lastUse }) where node.surface.isHidden && bytes > Self.budget {
            node.image.contents = nil
            node.snapshot = nil
            bytes -= node.byteCount
            node.byteCount = 0
            node.dirty = true
        }
    }

    private var displayResolution: CGFloat {
        max(0.25, (window?.backingScaleFactor ?? 2) * camera.scale)
    }

    private func hasSharpDragImage(_ node: Node) -> Bool {
        node.snapshot != nil && !node.dirty && node.resolution + 0.02 >= displayResolution
    }

    /// Upgrade once at pickup, never on each mouse-drag event. Keep the previous image stable
    /// while the staging host draws, then blend in its replacement without flashing live UI.
    private func prepareDragImages(for id: UUID) {
        dragPreparation?.cancel()
        let ids = board.selection.contains(id) ? board.selection : [id]
        dragImageIDs = Set(ids)
        let pending = ids.compactMap { nodes[$0] }.filter {
            !hasSharpDragImage($0) && !$0.entry.needsLiveContent && !$0.entry.isEditing && !$0.isScrolling
        }
        guard !pending.isEmpty else { return }
        for node in pending {
            activate(node, forCache: true)
            node.host.layoutSubtreeIfNeeded()
            prepareSnapshot(node)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.itemDrag?.id == id else { return }
            self.dragPreparation = nil
            for node in pending where self.nodes[node.entry.item.id] === node {
                node.host.layoutSubtreeIfNeeded()
                let pixels = node.surface.bounds.width * node.surface.bounds.height * pow(self.displayResolution, 2)
                let otherBytes = self.nodes.values.reduce(0) { $0 + $1.byteCount } - node.byteCount
                // A huge selection stays live rather than consuming unbounded bitmap memory.
                guard CGFloat(otherBytes) + pixels * 4 <= CGFloat(Self.budget),
                      self.capture(node, resolution: self.displayResolution) else {
                    self.activate(node)
                    continue
                }
                if self.itemDrag?.moved == true {
                    self.presentCache(node)
                }
            }
        }
        dragPreparation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func beginDrag(_ id: UUID, event: NSEvent) {
        guard let node = nodes[id] else { return }
        itemDrag = ItemDrag(id: id, origin: node.entry.item.origin, start: event.locationInWindow, scale: camera.scale)
        prepareDragImages(for: id)
    }

    private func drag(_ event: NSEvent) {
        guard var movement = itemDrag, let node = nodes[movement.id] else { return }
        if !movement.moved {
            board.beginHistoryAction()
            if node.host.superview != nil {
                node.host.layoutSubtreeIfNeeded()
                if hasSharpDragImage(node) {
                    if node.interactionDirty { _ = capture(node, resolution: displayResolution) }
                    node.host.removeFromSuperview()
                }
            }
            node.image.isHidden = node.host.superview != nil && !node.isStagingCache
            if interactingID == movement.id { interactingID = nil }
            movement.moved = true
            itemDrag = movement
            NSCursor.closedHand.set()
        }
        board.move(movement.id, to: CGPoint(x: movement.origin.x + (event.locationInWindow.x - movement.start.x) / movement.scale,
                                            y: movement.origin.y - (event.locationInWindow.y - movement.start.y) / movement.scale),
                   threshold: 8 / movement.scale, overhang: 84 / movement.scale)
        let content = window?.contentView
        var location = content?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        if let content, !content.isFlipped { location.y = content.bounds.maxY - location.y }
        WorktreeItemMove.updateDestination(board: board, id: movement.id, location: location)
        node.surface.alphaValue = board.trashTargetID == movement.id ? 0.5 : board.sidebarDrag?.id == movement.id ? 0 : 1
    }

    private func endDrag() {
        guard let movement = itemDrag else { return }
        dragPreparation?.cancel()
        dragPreparation = nil
        for id in dragImageIDs {
            if let node = nodes[id], node.host.superview != nil { node.dirty = true }
        }
        dragImageIDs = []
        scheduleRefresh()
        itemDrag = nil
        nodes[movement.id]?.surface.alphaValue = 1
        if movement.moved {
            WorktreeItemMove.end(board: board, id: movement.id, start: movement.origin, runtime: runtime)
            board.endHistoryAction()
            settlePositions()
        } else { board.select(movement.id) }
        NSCursor.arrow.set()
    }

    private func beginResize(_ id: UUID, handle: WorktreePhotoHandle, event: NSEvent) {
        guard let node = nodes[id], let frame = board.frame(of: id) else { return }
        let item = node.entry.item
        let inset = item.isQuestion ? 0 : WorktreeItemView.textPadding * 2
        let size = item.size ?? CGSize(width: max(1, frame.width - inset), height: max(1, frame.height - inset))
        itemResize = ItemResize(item: item, size: size, start: event.locationInWindow, handle: handle, scale: camera.scale)
        dragImageIDs = [id]
        board.beginHistoryAction()
        interactingID = id
        activate(node)
        handle.nativeResizeCursor.set()
    }

    private func resize(_ event: NSEvent) {
        guard let state = itemResize else { return }
        let delta = CGSize(width: event.locationInWindow.x - state.start.x, height: state.start.y - event.locationInWindow.y)
        let item = state.item, handle = state.handle
        if item.image != nil {
            let start = WorktreePhotoFrame(origin: item.origin, size: state.size,
                layout: item.photoLayout ?? WorktreePhotoGeometry.covering(state.size, frame: state.size))
            let result = WorktreePhotoResize.frame(from: start, handle: handle, translation: delta, zoom: state.scale)
            board.update(item.id) { $0.origin = result.origin; $0.size = result.size; $0.photoLayout = result.layout }
        } else if item.isQuestion {
            let dx = delta.width / state.scale, dy = delta.height / state.scale
            var size = state.size, origin = item.origin
            if handle == .right || handle == .bottomRight { size.width = max(240, state.size.width + dx) }
            if handle == .left || handle == .bottomLeft {
                size.width = max(240, state.size.width - dx)
                origin.x += state.size.width - size.width
            }
            if handle == .bottom || handle == .bottomLeft || handle == .bottomRight { size.height = max(140, state.size.height + dy) }
            board.update(item.id) { $0.origin = origin; $0.size = size }
        } else {
            let result = WorktreeTextBoxResize.frame(origin: item.origin, size: state.size, handle: handle,
                translation: delta, zoom: state.scale,
                minimumHeight: item.isHeading ? WorktreeItemView.headingLineHeight : WorktreeTextEditor.lineHeight)
            board.update(item.id) { $0.origin = result.origin; $0.size = result.size }
        }
    }

    private func endResize() {
        guard let state = itemResize else { return }
        itemResize = nil
        dragImageIDs = []
        board.endHistoryAction()
        if let node = nodes[state.item.id] { node.dirty = true }
        interactingID = nil
        scheduleRefresh()
        NSCursor.arrow.set()
    }

    private func interactionFrame(for node: Node, frame: CGRect) -> CGRect {
        // Include the top grip's complete 20pt hit target, as well as the side grip and label.
        let top = max(node.entry.item.label == nil ? 0 : 52, 24 / camera.scale)
        let left = 40 / camera.scale
        let edge = max(8, 8 / camera.scale)
        return CGRect(x: frame.minX - left, y: frame.minY - top,
                      width: max(frame.width + left, node.surface.bounds.width - Self.inset * 2) + edge,
                      height: frame.height + top + edge)
    }

    private func topGripFrame(for node: Node, frame: CGRect) -> CGRect? {
        let item = node.entry.item
        guard !item.isQuestion, !item.isInsight, !item.isSummarizing, !item.isHelp else { return nil }
        let box = item.image == nil ? frame : frame.insetBy(dx: WorktreeItemView.textPadding, dy: WorktreeItemView.textPadding)
        return WorktreeBoxGrip.hitFrame(in: box, zoom: camera.scale)
    }

    private func isNativeGrip(_ location: CGPoint, node: Node, frame: CGRect) -> Bool {
        if topGripFrame(for: node, frame: frame)?.contains(location) == true { return true }
        guard node.entry.item.isHeading else { return false }
        let glyph = WorktreeBoxGrip.glyphSize
        let side = CGRect(x: frame.minX - (glyph.width + 8) / camera.scale - 6,
                          y: frame.minY - 6, width: glyph.width / camera.scale + 12,
                          height: glyph.height / camera.scale + 12)
        return side.contains(location)
    }

    private func releaseHoverInteraction() {
        guard itemDrag == nil, itemResize == nil, let id = interactingID, let node = nodes[id],
              !node.entry.isEditing, !node.entry.needsLiveContent, !node.isScrolling else { return }
        interactingID = nil
        if node.host.superview != nil { node.dirty = true; scheduleRefresh() }
    }

    /// Cached pixels have no tracking areas. Wake only the newly hovered item so AppKit can
    /// install its real text, resize and move cursors without rebuilding other canvas items.
    func hover(world location: CGPoint?) {
        guard !isMoving, itemDrag == nil, itemResize == nil, movingIDs.isEmpty else { return }
        let id = location.flatMap { point in
            orderedIDs.reversed().first { id in
                guard let node = nodes[id], !node.surface.isHidden, let frame = board.frame(of: id) else { return false }
                return interactionFrame(for: node, frame: frame).contains(point)
            }
        }
        if id == nil { releaseHoverInteraction() }
        let overGrip: Bool
        if let id, let location, let node = nodes[id], let frame = board.frame(of: id) {
            overGrip = isNativeGrip(location, node: node, frame: frame)
        } else { overGrip = false }
        let resize = id.flatMap { id -> WorktreePhotoHandle? in
            guard let node = nodes[id], let location, let frame = board.frame(of: id) else { return nil }
            return WorktreeResizeHover.handle(at: location, item: node.entry.item, frame: frame, zoom: camera.scale)
        }
        if overGrip { NSCursor.openHand.set() }
        else if let resize { resize.nativeResizeCursor.set() }
        else if isOverNativeGrip {
            NSCursor.arrow.set()
            if let id, let node = nodes[id] { window?.invalidateCursorRects(for: node.host) }
        }
        isOverNativeGrip = overGrip || resize != nil
        let needsHost = id.flatMap { nodes[$0] }.map { $0.host.superview == nil || $0.snapshotPreparedAt != nil } ?? false
        guard id != hoveredID || needsHost else { return }
        if let previous = hoveredID, previous != id { board.setHovered(previous, false) }
        hoveredID = id
        if let id, let location, let node = nodes[id] {
            let local = world.convert(location, to: self)
            _ = hitTest(convert(local, to: superview))
            window?.invalidateCursorRects(for: node.host)
        } else {
            NSCursor.arrow.set()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit supplies hitTest points in the superview's coordinate system, which may
        // have the opposite vertical orientation to this flipped scene.
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        if itemDrag != nil || itemResize != nil { return dragReceiver }
        dragReceiver.itemID = nil
        dragReceiver.resizeHandle = nil
        let location = world.convert(localPoint, from: self)
        for id in orderedIDs.reversed() {
            guard let node = nodes[id], !node.surface.isHidden,
                  let frame = board.frame(of: id) else { continue }
            // Labels and the move grip sit just outside the ordinary item frame.
            let target = interactionFrame(for: node, frame: frame)
            guard target.contains(location) else { continue }
            if NSApp.currentEvent?.type == .leftMouseDown,
               !node.entry.needsLiveContent, !node.entry.isEditing, !node.isScrolling {
                if let handle = WorktreeResizeHover.handle(at: location, item: node.entry.item, frame: frame, zoom: camera.scale) {
                    dragReceiver.itemID = id
                    dragReceiver.resizeHandle = handle
                    return dragReceiver
                }
                let top = CGRect(x: frame.minX + 6 / camera.scale, y: frame.minY + 6 / camera.scale,
                                 width: frame.width - 12 / camera.scale, height: max(0, WorktreeItemView.cardPadding - 6 / camera.scale))
                let grip = CGRect(x: frame.minX - 40 / camera.scale, y: frame.minY + WorktreeItemView.cardPadding - 8 / camera.scale,
                                  width: 40 / camera.scale, height: 40 / camera.scale)
                let isConversationGrip = node.entry.item.isQuestion && node.snapshot != nil
                    && CACurrentMediaTime() >= node.captureAfter && (top.contains(location) || grip.contains(location))
                if isConversationGrip || isNativeGrip(location, node: node, frame: frame) {
                    dragReceiver.itemID = id
                    return dragReceiver
                }
            }
            if let previous = interactingID, previous != id, let old = nodes[previous],
               !old.entry.isEditing, !old.entry.needsLiveContent, !old.isScrolling,
               CACurrentMediaTime() >= old.captureAfter, !old.dirty, old.snapshot != nil {
                if old.interactionDirty {
                    old.host.layoutSubtreeIfNeeded()
                    _ = capture(old, resolution: max(0.25, old.resolution))
                }
                old.host.removeFromSuperview()
                old.image.isHidden = false
                old.surface.setAccessibilityElement(true)
            }
            if let previous = interactingID, previous != id, let old = nodes[previous],
               old.host.superview != nil, !old.entry.needsLiveContent, !old.entry.isEditing {
                old.dirty = true
                scheduleRefresh()
            }
            if NSApp.currentEvent?.type == .leftMouseDown, movingIDs.remove(id) != nil, let environment {
                node.host.rootView = root(for: node, environment: environment)
            }
            interactingID = id
            node.host.alphaValue = 1
            activate(node)
            node.host.layoutSubtreeIfNeeded()
            observeScroll(node)
            let hit = node.host.hitTest(localPoint)
            return hit
        }
        return nil
    }

    #if DEBUG
    var cacheStatistics: (nodes: Int, cached: Int, live: Int, visible: Int, bytes: Int, builds: Int) {
        (nodes.count, nodes.values.filter { $0.image.contents != nil }.count,
         nodes.values.filter { $0.host.superview != nil }.count, nodes.values.filter { !$0.surface.isHidden }.count,
         nodes.values.reduce(0) { $0 + $1.byteCount }, builds)
    }
    func cachedImage(for id: UUID) -> CGImage? { nodes[id]?.snapshot }
    func presentationState(for id: UUID) -> (imageVisible: Bool, liveVisible: Bool, staging: Bool)? {
        guard let node = nodes[id] else { return nil }
        return (node.snapshot != nil && !node.image.isHidden,
                node.host.superview != nil && node.host.alphaValue > 0, node.isStagingCache)
    }

    #endif

    func stop() {
        isStopped = true
        clearPointer()
        if let pointerArea { removeTrackingArea(pointerArea) }
        pointerArea = nil
        for observer in pointerObservers { NotificationCenter.default.removeObserver(observer) }
        pointerObservers = []
        if let movement = itemDrag, movement.moved {
            board.endMove()
            board.sidebarDrag = nil
            board.trashTargetID = nil
            board.endHistoryAction()
        }
        if itemDrag != nil { NSCursor.arrow.set() }
        itemDrag = nil
        if itemResize != nil { board.endHistoryAction(); NSCursor.arrow.set() }
        itemResize = nil
        dragReceiver.itemID = nil
        dragReceiver.resizeHandle = nil
        hoveredID = nil
        dragPreparation?.cancel()
        dragPreparation = nil
        dragImageIDs = []
        settle?.cancel(); refresh?.cancel(); positionSettle?.cancel()
        for node in nodes.values {
            node.presentation?.cancel()
            node.scrollSettle?.cancel()
            if let observer = node.scrollObserver { NotificationCenter.default.removeObserver(observer) }
            node.host.removeFromSuperview()
            node.surface.removeFromSuperview()
        }
        nodes.removeAll()
    }
}

private final class WorktreeNodeHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}

/// Shared move destinations preserve Trash, sidebar copying, and history behavior.
@MainActor enum WorktreeItemMove {
    static func updateDestination(board: WorktreeBoard, id: UUID, location: CGPoint) {
        board.trashTargetID = board.trashFrame.insetBy(dx: -12, dy: -12).contains(location) ? id : nil
        // Over the sidebar, a conversation started here becomes the sidebar's chip.
        if WorktreeBoard.sidebarFrame.contains(location), let title = board.sidebarTitle(for: id) {
            if board.sidebarDrag == nil {
                withAnimation(.springQuick) { board.sidebarDrag = .init(id: id, title: title, location: location) }
            } else {
                board.sidebarDrag?.location = location
            }
        } else if board.sidebarDrag != nil {
            withAnimation(.springQuick) { board.sidebarDrag = nil }
        }
    }
    static func end(board: WorktreeBoard, id: UUID, start: CGPoint?, runtime: MacApplicationRuntime) {
        board.endMove()
        if board.trashTargetID == id {
            withAnimation(.springQuick) { board.delete(id) }
        } else if board.sidebarDrag?.id == id {
            // The sidebar gets a copy; the window springs back to where it was.
            withAnimation(.springStandard) {
                if let start { board.update(id) { $0.origin = start } }
                board.sidebarDrag = nil
            }
            board.dropOnSidebar(id, runtime: runtime)
        }
        board.trashTargetID = nil
    }
}

/// Match the resize targets even while their SwiftUI cursor regions are being reattached.
enum WorktreeResizeHover {
    static func handle(at point: CGPoint, item: WorktreeBoard.Item, frame: CGRect, zoom: CGFloat) -> WorktreePhotoHandle? {
        guard !item.isInsight, !item.isSummarizing, !item.isHelp else { return nil }
        let box = item.image == nil ? frame : frame.insetBy(dx: WorktreeItemView.textPadding, dy: WorktreeItemView.textPadding)
        let local = CGPoint(x: point.x - box.minX, y: point.y - box.minY)
        if item.isQuestion {
            let w = box.width, h = box.height
            if CGRect(x: -4, y: h - 12, width: 16, height: 16).contains(local) { return .bottomLeft }
            if CGRect(x: w - 12, y: h - 12, width: 16, height: 16).contains(local) { return .bottomRight }
            if CGRect(x: -4, y: 0, width: 8, height: h - 16).contains(local) { return .left }
            if CGRect(x: w - 4, y: 0, width: 8, height: h - 16).contains(local) { return .right }
            if CGRect(x: 16, y: h - 4, width: max(0, w - 32), height: 8).contains(local) { return .bottom }
            return nil
        }
        let thickness: CGFloat = item.image == nil ? 8 / zoom : 8
        let corner: CGFloat = item.image == nil ? 12 / zoom : 16
        // Corners take precedence over side targets, matching the visible box handles.
        for handle in WorktreePhotoHandle.allCases.filter({ $0.corner }) + [.left, .right, .bottom] {
            let size = CGSize(width: handle.corner ? corner : handle.horizontal ? thickness : max(0, box.width - corner),
                              height: handle.corner ? corner : handle.horizontal ? max(0, box.height - corner) : thickness)
            let center = handle.point(in: box.size)
            if CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height).contains(local) { return handle }
        }
        return nil
    }
}

private extension WorktreePhotoHandle {
    var nativeResizeCursor: NSCursor {
        let position: NSCursor.FrameResizePosition
        switch self {
        case .left: position = .left
        case .right: position = .right
        case .top: position = .top
        case .bottom: position = .bottom
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        }
        return .frameResize(position: position, directions: .all)
    }
}
