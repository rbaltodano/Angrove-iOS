import SwiftUI

/// The pointer in canvas (world) space. Observed only by the text boxes that fade in near it, so
/// pointer movement never re-renders the rest of the canvas.
@MainActor @Observable final class WorktreeCanvasPointer {
    var world: CGPoint?
}

/// A note's box, as Figma draws a text layer's: a frame with a square at each corner. Its edges
/// and corners resize the note. Brand green at 50%, shown only while the pointer is within 84
/// screen points of it.
enum WorktreeTextBoxResize {
    static let minimumWidth: CGFloat = 40
    static let revealDistance: CGFloat = 84

    /// The note's new origin and text size. Width wraps the text; height is a minimum, so text
    /// never overflows. Translation is in screen points.
    static func frame(origin: CGPoint, size: CGSize, handle: WorktreePhotoHandle,
                      translation: CGSize, zoom: CGFloat) -> (origin: CGPoint, size: CGSize) {
        let dx = translation.width / zoom, dy = translation.height / zoom
        var origin = origin
        var result = size
        let movesX = handle.corner || handle.horizontal
        let movesY = handle.corner || !handle.horizontal
        if movesX {
            result.width = max(minimumWidth, size.width + (handle.left ? -dx : dx))
            if handle.left { origin.x += size.width - result.width }
        }
        if movesY {
            result.height = max(WorktreeTextEditor.lineHeight, size.height + (handle.top ? -dy : dy))
            if handle.top { origin.y += size.height - result.height }
        }
        return (origin, result)
    }

    /// Whether a world point lies within `revealDistance` screen points of a world rect.
    static func isNear(_ point: CGPoint?, to rect: CGRect?, zoom: CGFloat) -> Bool {
        guard let point, let rect else { return false }
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy) * zoom <= revealDistance
    }
}

struct WorktreeTextBox: View {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let zoom: CGFloat
    let pointer: WorktreeCanvasPointer
    @State private var start: (origin: CGPoint, size: CGSize)?
    /// Where the resize was pressed, in the box's own coordinates; a 75% glow ripples out from it
    /// around the whole outline and holds until release.
    @State private var pressPoint: CGPoint?
    @State private var glow: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let square: CGFloat = 7
    private var color: Color { AngroveTheme.Colors.lightGreen.opacity(0.5) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let isVisible = start != nil || WorktreeTextBoxResize.isNear(pointer.world, to: board.frame(of: item.id), zoom: zoom)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().strokeBorder(color, lineWidth: 1 / zoom)
                    ForEach([WorktreePhotoHandle.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                        Rectangle()
                            .fill(AngroveTheme.Colors.canvas)
                            .overlay(Rectangle().strokeBorder(color, lineWidth: 1 / zoom))
                            .frame(width: Self.square / zoom, height: Self.square / zoom)
                            .position(position(corner, in: size))
                    }
                }
                .opacity(isVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isVisible)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                illumination(in: size)

                ForEach(WorktreePhotoHandle.allCases, id: \.self) { handle in
                    handleArea(handle, in: size)
                }
            }
        }
    }

    /// The outline and corner squares at 75%, revealed by a soft-edged circle growing from the
    /// press until it covers the whole box.
    private func illumination(in size: CGSize) -> some View {
        let reach = hypot(size.width, size.height) * 1.25
        // Another 50% over the 50% outline composites to 75%.
        let bright = AngroveTheme.Colors.lightGreen.opacity(0.5)
        return ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(bright, lineWidth: 1 / zoom)
            ForEach([WorktreePhotoHandle.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                Rectangle()
                    .strokeBorder(bright, lineWidth: 1 / zoom)
                    .frame(width: Self.square / zoom, height: Self.square / zoom)
                    .position(position(corner, in: size))
            }
        }
        .mask(alignment: .topLeading) {
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.7),
                                             .init(color: .clear, location: 1)],
                                     center: .center, startRadius: 0, endRadius: reach))
                .frame(width: reach * 2, height: reach * 2)
                .scaleEffect(glow, anchor: .center)
                .position(pressPoint ?? CGPoint(x: size.width / 2, y: size.height / 2))
        }
        .opacity(pressPoint == nil ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Pressing a resize edge: the outline lights up from the press and the dot grid ripples there.
    private func beginGlow(at world: CGPoint?) {
        guard let world, let frame = board.frame(of: item.id) else {
            pressPoint = CGPoint(x: 0, y: 0)
            glow = 1
            return
        }
        board.pulse(at: world)
        pressPoint = CGPoint(x: world.x - frame.minX, y: world.y - frame.minY)
        glow = 0
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { glow = 1 }
    }

    private func endGlow() {
        withAnimation(.easeOut(duration: 0.3)) { pressPoint = nil } completion: { glow = 0 }
    }

    private func handleArea(_ handle: WorktreePhotoHandle, in size: CGSize) -> some View {
        let thickness = 8 / zoom, corner = 12 / zoom
        let width = handle.corner ? corner : handle.horizontal ? thickness : max(0, size.width - corner)
        let height = handle.corner ? corner : handle.horizontal ? max(0, size.height - corner) : thickness
        return Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: handle.cursor))
            .position(position(handle, in: size))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacWorktreeView.canvasSpace))
                .onChanged { value in
                    if start == nil {
                        board.beginHistoryAction()
                        beginGlow(at: pointer.world)
                        // The text's own size: the measured frame less the note's padding.
                        let padding = WorktreeItemView.textPadding * 2
                        start = (item.origin, item.size ?? CGSize(width: max(0, size.width - padding),
                                                                  height: max(0, size.height - padding)))
                    }
                    guard let start else { return }
                    let frame = WorktreeTextBoxResize.frame(origin: start.origin, size: start.size, handle: handle,
                                                           translation: value.translation, zoom: zoom)
                    board.update(item.id) { $0.origin = frame.origin; $0.size = frame.size }
                }
                .onEnded { _ in start = nil; endGlow(); board.endHistoryAction() })
            .accessibilityLabel("Resize text box")
    }

    private func position(_ handle: WorktreePhotoHandle, in size: CGSize) -> CGPoint {
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
