import AppKit
import SwiftUI

/// A Board's card preview: the real canvas, zoomed out to fit everything on it, as Figma shows a
/// file. Rendered in light and dark on a transparent background so the card's canvas shows through.
struct WorktreeSnapshotImages: Codable, Equatable {
    var light: Data?
    var dark: Data?
    /// The document's `updatedAt` when rendered; a later edit makes the snapshot stale.
    var documentUpdatedAt: Date?

    var isEmpty: Bool { light == nil && dark == nil }
}

/// Decoded once per snapshot so cards don't decode PNGs on every render.
struct WorktreeSnapshot {
    let light: NSImage?
    let dark: NSImage?
    let documentUpdatedAt: Date?

    init?(_ images: WorktreeSnapshotImages) {
        guard !images.isEmpty else { return nil }
        light = images.light.flatMap(NSImage.init(data:))
        dark = images.dark.flatMap(NSImage.init(data:))
        documentUpdatedAt = images.documentUpdatedAt
    }

    func image(for scheme: ColorScheme) -> NSImage? {
        scheme == .dark ? dark ?? light : light ?? dark
    }
}

/// Snapshots hold Board content, so they live beside the Boards in the encrypted personal store,
/// one file per Board.
enum WorktreeSnapshotStore {
    static func key(_ id: UUID) -> String { "angrove.worktree.snapshot.\(id.uuidString)" }

    static func load(_ id: UUID) -> WorktreeSnapshotImages? {
        guard let store = WorktreeStore.store else { return nil }
        return SerializedPersonalStore.shared.load(WorktreeSnapshotImages.self, key: key(id), store: store)
    }

    static func save(_ images: WorktreeSnapshotImages, for id: UUID) {
        guard let store = WorktreeStore.store else { return }
        SerializedPersonalStore.shared.save(images, key: key(id), store: store)
    }

    /// Overwrites a deleted Board's snapshot so none of its content remains on disk.
    static func remove(_ id: UUID) { save(WorktreeSnapshotImages(), for: id) }
}

@MainActor @Observable final class WorktreeSnapshotCamera {
    var scale: CGFloat = 0.25
    var offset: CGSize = .zero
}

/// Renders Boards offscreen from a throwaway copy, so the open Board, its sessions and the
/// visible window are never touched.
@MainActor enum WorktreeSnapshotRenderer {
    /// Off until rendering is verified in the app; cards show drawn previews meanwhile.
    static let isEnabled = false
    static let size = CGSize(width: 720, height: 330)
    private static let inset: CGFloat = 28
    /// A Board with one small note shouldn't fill the card.
    private static let maxScale: CGFloat = 0.55

    static func render(_ document: WorktreeDocument) async -> WorktreeSnapshotImages? {
        guard !document.items.isEmpty else { return nil }
        let board = WorktreeBoard(document: document)
        let camera = WorktreeSnapshotCamera()
        fit(camera, to: estimatedBounds(of: document))
        let host = NSHostingView(rootView: WorktreeSnapshotCanvas(board: board, camera: camera))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -40_000, y: -40_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.alphaValue = 0
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        window.orderBack(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        // Let items lay out (and photos decode), then fit to their measured frames.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return nil }
        let measured = board.items.compactMap { board.frame(of: $0.id) }
        if let bounds = measured.reduce(nil, { (union: CGRect?, frame) in union?.union(frame) ?? frame }) {
            fit(camera, to: bounds)
        }

        var images = WorktreeSnapshotImages(documentUpdatedAt: document.updatedAt)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: name)
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return nil }
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = bitmap.representation(using: .png, properties: [:])
            if name == .darkAqua { images.dark = png } else { images.light = png }
        }
        return images.isEmpty ? nil : images
    }

    private static func fit(_ camera: WorktreeSnapshotCamera, to bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min((size.width - inset * 2) / bounds.width, (size.height - inset * 2) / bounds.height, maxScale)
        camera.scale = scale
        camera.offset = CGSize(width: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                               height: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
    }

    private static func estimatedBounds(of document: WorktreeDocument) -> CGRect {
        document.items.map { WorktreeThumbnailShape($0).frame }
            .reduce(CGRect.null) { $0.union($1) }
    }
}

/// The Board's items exactly as the canvas draws them, without chrome, guides or the dot grid.
private struct WorktreeSnapshotCanvas: View {
    let board: WorktreeBoard
    let camera: WorktreeSnapshotCamera
    @State private var pointer = WorktreeCanvasPointer()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(board.items) { item in
                WorktreeItemView(board: board, item: item, scale: camera.scale, runtime: .shared, pointer: pointer)
                    .equatable()
                    .fixedSize()
                    .offset(x: item.origin.x, y: item.origin.y)
            }
        }
        .frame(width: 0, height: 0, alignment: .topLeading)
        .scaleEffect(camera.scale, anchor: .topLeading)
        .offset(camera.offset)
        .frame(width: WorktreeSnapshotRenderer.size.width, height: WorktreeSnapshotRenderer.size.height,
               alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .transaction { $0.disablesAnimations = true }
    }
}
