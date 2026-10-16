import SwiftUI

/// Full image bounds relative to the crop frame. Cropping never changes or discards image data.
struct WorktreePhotoLayout: Codable, Equatable {
    var contentSize: CGSize
    var offset: CGPoint = .zero
}

struct WorktreePhotoFrame: Equatable {
    var origin: CGPoint
    var size: CGSize
    var layout: WorktreePhotoLayout
}

enum WorktreePhotoHandle: CaseIterable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    var left: Bool { [.left, .topLeft, .bottomLeft].contains(self) }
    var top: Bool { [.top, .topLeft, .topRight].contains(self) }
    var corner: Bool { ![.left, .right, .top, .bottom].contains(self) }
    var horizontal: Bool { self == .left || self == .right }

    var cursor: FrameResizePosition {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

enum WorktreePhotoResize {
    /// Translation and snapping are measured in screen points, independently of canvas zoom.
    static func frame(from start: WorktreePhotoFrame, handle: WorktreePhotoHandle,
                      translation: CGSize, zoom: CGFloat) -> WorktreePhotoFrame {
        let dx = translation.width / zoom, dy = translation.height / zoom
        var result = start
        let minimum = CGSize(width: min(32, start.size.width), height: min(32, start.size.height))
        if handle.corner {
            let x = handle.left ? -dx : dx, y = handle.top ? -dy : dy
            let projection = (x * start.size.width + y * start.size.height)
                / (start.size.width * start.size.width + start.size.height * start.size.height)
            let factor = max(max(minimum.width / start.size.width, minimum.height / start.size.height), 1 + projection)
            result.size = CGSize(width: start.size.width * factor, height: start.size.height * factor)
            result.layout = WorktreePhotoGeometry.covering(start.layout.contentSize, frame: result.size)
            if handle.left { result.origin.x += start.size.width - result.size.width }
            if handle.top { result.origin.y += start.size.height - result.size.height }
            return result
        }

        let aspect = start.layout.contentSize.width / start.layout.contentSize.height
        if handle.horizontal {
            var width = max(start.size.width + (handle.left ? -dx : dx), minimum.width)
            let originalAspectWidth = start.size.height * aspect
            if abs(width - originalAspectWidth) * zoom <= 16,
               originalAspectWidth >= minimum.width {
                width = originalAspectWidth
            }
            result.size.width = width
            if handle.left {
                let change = start.size.width - width
                result.origin.x += change
            }
        } else {
            var height = max(start.size.height + (handle.top ? -dy : dy), minimum.height)
            let originalAspectHeight = start.size.width / aspect
            if abs(height - originalAspectHeight) * zoom <= 16,
               originalAspectHeight >= minimum.height {
                height = originalAspectHeight
            }
            result.size.height = height
            if handle.top {
                let change = start.size.height - height
                result.origin.y += change
            }
        }
        result.layout = WorktreePhotoGeometry.covering(start.layout.contentSize, frame: result.size)
        return result
    }
}

/// Side handles change the crop; corner handles scale the entire cropped photo proportionally.
struct WorktreePhotoResizeHandles: View {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let size: CGSize
    let layout: WorktreePhotoLayout
    let zoom: CGFloat
    @State private var start: WorktreePhotoFrame?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(WorktreePhotoHandle.allCases, id: \.self) { handle in
                let corner = handle.corner
                let width = corner ? 16.0 : handle.horizontal ? 8.0 : max(0, size.width - 32)
                let height = corner ? 16.0 : handle.horizontal ? max(0, size.height - 32) : 8.0
                Color.clear
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .pointerStyle(.frameResize(position: handle.cursor))
                    .position(position(handle))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacWorktreeView.canvasSpace))
                        .onChanged { value in
                            if start == nil { board.select(item.id); board.beginHistoryAction() }
                            let initial = start ?? WorktreePhotoFrame(origin: item.origin, size: size, layout: layout)
                            start = initial
                            let frame = WorktreePhotoResize.frame(from: initial, handle: handle,
                                                                 translation: value.translation, zoom: zoom)
                            board.update(item.id) {
                                $0.origin = frame.origin; $0.size = frame.size; $0.photoLayout = frame.layout
                            }
                        }
                        .onEnded { _ in start = nil; board.endHistoryAction() })
                    .accessibilityLabel(corner ? "Resize photo proportionally" : "Crop photo")
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func position(_ handle: WorktreePhotoHandle) -> CGPoint {
        switch handle {
        case .left: CGPoint(x: 0, y: size.height / 2)
        case .right: CGPoint(x: size.width, y: size.height / 2)
        case .top: CGPoint(x: size.width / 2, y: 0)
        case .bottom: CGPoint(x: size.width / 2, y: size.height)
        case .topLeft: .zero
        case .topRight: CGPoint(x: size.width, y: 0)
        case .bottomLeft: CGPoint(x: 0, y: size.height)
        case .bottomRight: CGPoint(x: size.width, y: size.height)
        }
    }
}
