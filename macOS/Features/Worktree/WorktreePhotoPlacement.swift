import AppKit
import SwiftUI

/// A decoded photo ready to follow the pointer, then land on the canvas.
struct WorktreePhotoAsset: Identifiable {
    let file: UploadedFile
    let image: NSImage
    var id: UUID { file.id }
    var placedSize: CGSize {
        WorktreePhotoGeometry.fitted(image.size, rotation: 0, maximum: 1000)
    }
}

enum WorktreePhotoGeometry {
    static func covering(_ natural: CGSize, frame: CGSize) -> WorktreePhotoLayout {
        guard natural.width > 0, natural.height > 0 else { return WorktreePhotoLayout(contentSize: frame) }
        let ratio = max(frame.width / natural.width, frame.height / natural.height)
        let content = CGSize(width: natural.width * ratio, height: natural.height * ratio)
        return WorktreePhotoLayout(contentSize: content,
            offset: CGPoint(x: (frame.width - content.width) / 2, y: (frame.height - content.height) / 2))
    }

    static func fitted(_ size: CGSize, rotation: Double, maximum: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else {
            return CGSize(width: maximum, height: maximum)
        }
        let angle = rotation * .pi / 180
        let width = abs(cos(angle)) * size.width + abs(sin(angle)) * size.height
        let height = abs(sin(angle)) * size.width + abs(cos(angle)) * size.height
        let ratio = min(1, maximum / max(width, height))
        return CGSize(width: width * ratio, height: height * ratio)
    }
}

/// Owns high-frequency pointer state so following the mouse does not invalidate the board.
struct WorktreePhotoPlacement: View {
    let asset: WorktreePhotoAsset
    let onPlace: (CGPoint) -> Void
    var onPan: (CGSize) -> Void = { _ in }
    @State private var pointer: CGPoint?
    @State private var position = CGPoint.zero
    @State private var tilt: Double = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorktreePhotoPointerSurface(onMove: follow, onPlace: onPlace, onPan: onPan)
            if pointer != nil {
                let size = WorktreePhotoGeometry.fitted(asset.image.size, rotation: asset.file.rotationDegrees, maximum: 120)
                WorktreePhotoContent(image: asset.image, rotation: asset.file.rotationDegrees, size: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .rotationEffect(.degrees(reduceMotion ? 2 : tilt), anchor: .topLeading)
                    .offset(x: position.x + 24, y: position.y + 24)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task(id: pointer) {
            guard pointer != nil else { return }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            withAnimation(reduceMotion ? nil : .springLively) { tilt = 2 }
        }
        .accessibilityLabel("Click to place photo. Press Escape to cancel.")
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
            // Appear beside the pointer immediately; subsequent movement has spring velocity.
            position = next
        }
    }
}

/// Keeps the file's own rotation inside its fitted bounds, independently of preview tilt.
struct WorktreePhotoContent: View {
    let image: NSImage
    let rotation: Double
    let size: CGSize

    var body: some View {
        let natural = WorktreePhotoGeometry.fitted(image.size, rotation: rotation, maximum: .greatestFiniteMagnitude)
        let ratio = min(size.width / natural.width, size.height / natural.height)
        Image(nsImage: image)
            .resizable()
            .frame(width: image.size.width * ratio, height: image.size.height * ratio)
            .rotationEffect(.degrees(rotation))
            .frame(width: size.width, height: size.height)
    }
}

/// Captures placement clicks even over existing cards. It uses the current window pointer on
/// mounting, so choosing a photo does not require an extra mouse movement to show the preview.
struct WorktreePhotoPointerSurface: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void
    let onPlace: (CGPoint) -> Void
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.onMove = onMove
        view.onPlace = onPlace
        view.onPan = onPan
    }

    final class Surface: NSView {
        var onMove: ((CGPoint?) -> Void)?
        var onPlace: ((CGPoint) -> Void)?
        var onPan: ((CGSize) -> Void)?
        private var mouseStart: CGPoint?
        private var previousMouse: CGPoint?
        private var isPanning = false
        private var tracking: NSTrackingArea?
        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero,
                options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
            addTrackingArea(area)
            tracking = area
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                self.onMove?(self.bounds.contains(point) ? point : nil)
            }
        }

        override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
        override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            mouseStart = point
            previousMouse = point
            isPanning = false
        }

        override func mouseDragged(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onMove?(point)
            guard let start = mouseStart else { return }
            if !isPanning, hypot(point.x - start.x, point.y - start.y) >= 3 {
                isPanning = true
                previousMouse = start
            }
            if isPanning, let previous = previousMouse {
                onPan?(CGSize(width: point.x - previous.x, height: point.y - previous.y))
                previousMouse = point
            }
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseStart = nil; previousMouse = nil; isPanning = false }
            guard mouseStart != nil, !isPanning else { return }
            onPlace?(convert(event.locationInWindow, from: nil))
        }
    }
}
