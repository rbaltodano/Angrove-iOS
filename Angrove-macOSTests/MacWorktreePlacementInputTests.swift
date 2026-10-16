import AppKit
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacWorktreePlacementInputTests {
    @Test func clickPlacesOnlyOnRelease() throws {
        let surface = WorktreePhotoPointerSurface.Surface()
        let window = mount(surface)
        defer { window.contentView = nil; window.close() }
        var placements: [CGPoint] = []
        surface.onPlace = { placements.append($0) }
        surface.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 50, y: 60), surface: surface, window: window))
        #expect(placements.isEmpty)
        surface.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 50, y: 60), surface: surface, window: window))
        #expect(placements == [CGPoint(x: 50, y: 60)])
    }

    @Test func draggingPansKeepsPreviewFollowingAndDoesNotPlaceEvenAfterReturningToStart() throws {
        let surface = WorktreePhotoPointerSurface.Surface()
        let window = mount(surface)
        defer { window.contentView = nil; window.close() }
        var camera = CanvasScrollTransform(scale: 1.5, offset: .zero)
        var placements = 0
        var pointer: CGPoint?
        surface.onPan = { camera.offset.width += $0.width; camera.offset.height += $0.height }
        surface.onPlace = { _ in placements += 1 }
        surface.onMove = { pointer = $0 }
        let start = CGPoint(x: 50, y: 60)
        surface.mouseDown(with: try event(.leftMouseDown, at: start, surface: surface, window: window))
        surface.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 80, y: 90), surface: surface, window: window))
        #expect(camera.offset == CGSize(width: 30, height: 30))
        #expect(camera.scale == 1.5)
        #expect(pointer == CGPoint(x: 80, y: 90))
        surface.mouseDragged(with: try event(.leftMouseDragged, at: start, surface: surface, window: window))
        surface.mouseUp(with: try event(.leftMouseUp, at: start, surface: surface, window: window))
        #expect(camera.offset == .zero)
        #expect(placements == 0)
    }

    private func mount(_ surface: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        return window
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, surface: NSView, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: surface.convert(point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
    }
}
