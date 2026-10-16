import SwiftUI

/// The pointer in canvas (world) space, and the items whose boxes it is near. The position itself
/// is not observed; `nearIDs` changes only when the pointer crosses a box's 84-point line, so
/// moving the mouse re-renders nothing until a box should fade in or out.
@MainActor @Observable final class WorktreeCanvasPointer {
    @ObservationIgnored private(set) var world: CGPoint?
    private(set) var nearIDs: Set<UUID> = []

    func update(world: CGPoint?, board: WorktreeBoard, zoom: CGFloat) {
        self.world = world
        var near = Set<UUID>()
        if world != nil {
            for item in board.items where WorktreeTextBoxResize.isNear(world, to: board.frame(of: item.id), zoom: zoom) {
                near.insert(item.id)
            }
        }
        if near != nearIDs { nearIDs = near }
    }
}

/// A note's, heading's or photo's box, as Figma draws a layer's: a frame with a square at each
/// corner. Its edges and corners resize it. Brand green at 50%, shown only while the pointer is
/// within 84 screen points of it.
enum WorktreeTextBoxResize {
    static let minimumWidth: CGFloat = 40
    static let revealDistance: CGFloat = 84

    /// The note's new origin and text size. Width wraps the text; height is a minimum, so text
    /// never overflows. Translation is in screen points.
    static func frame(origin: CGPoint, size: CGSize, handle: WorktreePhotoHandle,
                      translation: CGSize, zoom: CGFloat,
                      minimumHeight: CGFloat = WorktreeTextEditor.lineHeight) -> (origin: CGPoint, size: CGSize) {
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
            result.height = max(minimumHeight, size.height + (handle.top ? -dy : dy))
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

/// The box's look: a 1pt outline and 7pt corner squares, constant on screen at any zoom. While a
/// resize is held, a second 50% layer (75% together) is revealed by a soft-edged circle growing
/// from the press.
struct WorktreeBoxChrome: View {
    let size: CGSize
    let zoom: CGFloat
    let isVisible: Bool
    let press: WorktreeBoxPress

    private static let square: CGFloat = 7
    private static let corners: [WorktreePhotoHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    private var color: Color { AngroveTheme.Colors.lightGreen.opacity(0.5) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Rectangle().strokeBorder(color, lineWidth: 1 / zoom)
                ForEach(Self.corners, id: \.self) { corner in
                    Rectangle()
                        .fill(AngroveTheme.Colors.canvas)
                        .overlay(Rectangle().strokeBorder(color, lineWidth: 1 / zoom))
                        .frame(width: Self.square / zoom, height: Self.square / zoom)
                        .position(corner.point(in: size))
                }
            }
            .opacity(isVisible || press.point != nil ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isVisible || press.point != nil)
            illumination
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var illumination: some View {
        let reach = hypot(size.width, size.height) * 1.25
        // Another 50% over the 50% outline composites to 75%.
        return ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(color, lineWidth: 1 / zoom)
            ForEach(Self.corners, id: \.self) { corner in
                Rectangle()
                    .strokeBorder(color, lineWidth: 1 / zoom)
                    .frame(width: Self.square / zoom, height: Self.square / zoom)
                    .position(corner.point(in: size))
            }
        }
        .mask(alignment: .topLeading) {
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.7),
                                             .init(color: .clear, location: 1)],
                                     center: .center, startRadius: 0, endRadius: reach))
                .frame(width: reach * 2, height: reach * 2)
                .scaleEffect(press.glow, anchor: .center)
                .position(press.point ?? CGPoint(x: size.width / 2, y: size.height / 2))
        }
        .opacity(press.point == nil ? 0 : 1)
    }
}

/// A held resize: where it was pressed, in the box's coordinates, and how far the glow has spread.
struct WorktreeBoxPress {
    var point: CGPoint?
    var glow: CGFloat = 0

    /// Pressing a resize edge: the dot grid ripples from the press and the outline lights from it.
    /// `inset` is the box's distance inside the item's frame (a photo's box hugs the picture).
    /// Then animate `glow` to 1 to spread the light.
    @MainActor mutating func begin(board: WorktreeBoard, itemID: UUID, world: CGPoint?, inset: CGFloat = 0) {
        guard let world, let frame = board.frame(of: itemID) else {
            point = .zero
            glow = 1
            return
        }
        board.pulse(at: world)
        point = CGPoint(x: world.x - frame.minX - inset, y: world.y - frame.minY - inset)
        glow = 0
    }
}

extension WorktreePhotoHandle {
    func point(in size: CGSize) -> CGPoint {
        switch self {
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

/// Moving an item from its box: the item's own move, so snapping, Trash and the sidebar still work.
struct WorktreeBoxMove {
    let changed: (DragGesture.Value) -> Void
    let ended: () -> Void
}

/// The box's move grip: the canvas grip turned on its side, centred 8pt above the top line.
/// Hidden until the pointer is near; it glows while hovered or dragged. Its drag, like the top
/// edge's, moves the item and never resizes it.
struct WorktreeBoxGrip: View {
    let width: CGFloat
    let zoom: CGFloat
    let isVisible: Bool
    let move: WorktreeBoxMove
    @State private var isHovered = false
    @State private var isDragging = false

    private static let size = CGSize(width: 7.5, height: 12)
    private static let gap: CGFloat = 8

    var body: some View {
        let isLit = isHovered || isDragging
        Image("WorktreeGrip")
            .renderingMode(.template)
            .resizable()
            .frame(width: Self.size.width / zoom, height: Self.size.height / zoom)
            .rotationEffect(.degrees(90))
            .foregroundStyle(AngroveTheme.Colors.lightGreen.opacity(isLit ? 0.75 : 0.5))
            .shadow(color: AngroveTheme.Colors.lightGreen.opacity(isLit ? 0.6 : 0), radius: 4 / zoom)
            // A comfortable target around the small glyph.
            .frame(width: 28 / zoom, height: 20 / zoom)
            .contentShape(Rectangle())
            .opacity(isVisible || isLit ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isVisible || isLit)
            .animation(.easeOut(duration: 0.15), value: isLit)
            .onHover { isHovered = $0 }
            .pointerStyle(isDragging ? .grabActive : .grabIdle)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { isDragging = true; move.changed($0) }
                .onEnded { _ in isDragging = false; move.ended() })
            // Rotated, the grip is 12 wide and 7.5 tall; its centre sits 8pt plus half that above the line.
            .position(x: width / 2, y: -(Self.gap + Self.size.width / 2) / zoom)
            .accessibilityLabel("Move")
    }
}

/// The top edge between the corners moves the item rather than resizing it.
struct WorktreeBoxTopEdge: View {
    let width: CGFloat
    let zoom: CGFloat
    let move: WorktreeBoxMove

    var body: some View {
        Color.clear
            .frame(width: max(0, width - 12 / zoom), height: 8 / zoom)
            .contentShape(Rectangle())
            .pointerStyle(.grabIdle)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged(move.changed)
                .onEnded { _ in move.ended() })
            .position(x: width / 2, y: 0)
            .accessibilityHidden(true)
    }
}

/// A note's or heading's box. Edges set the wrap width and a minimum height; corners do both.
struct WorktreeTextBox: View {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let zoom: CGFloat
    let pointer: WorktreeCanvasPointer
    let move: WorktreeBoxMove
    /// One line: 28pt for a note, 56pt for a heading.
    var minimumHeight: CGFloat = WorktreeTextEditor.lineHeight
    @State private var start: (origin: CGPoint, size: CGSize)?
    @State private var press = WorktreeBoxPress()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let isVisible = start != nil || pointer.nearIDs.contains(item.id)
            ZStack(alignment: .topLeading) {
                WorktreeBoxChrome(size: size, zoom: zoom, isVisible: isVisible, press: press)
                ForEach(WorktreePhotoHandle.allCases.filter { $0 != .top }, id: \.self) { handle in
                    handleArea(handle, in: size)
                }
                WorktreeBoxTopEdge(width: size.width, zoom: zoom, move: move)
                WorktreeBoxGrip(width: size.width, zoom: zoom, isVisible: isVisible, move: move)
            }
        }
    }

    private func handleArea(_ handle: WorktreePhotoHandle, in size: CGSize) -> some View {
        let thickness = 8 / zoom, corner = 12 / zoom
        let width = handle.corner ? corner : handle.horizontal ? thickness : max(0, size.width - corner)
        let height = handle.corner ? corner : handle.horizontal ? max(0, size.height - corner) : thickness
        return Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: handle.cursor))
            .position(handle.point(in: size))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacWorktreeView.canvasSpace))
                .onChanged { value in
                    if start == nil {
                        board.beginHistoryAction()
                        press.begin(board: board, itemID: item.id, world: pointer.world)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { press.glow = 1 }
                        // The text's own size: the measured frame less the item's padding.
                        let padding = WorktreeItemView.textPadding * 2
                        start = (item.origin, item.size ?? CGSize(width: max(0, size.width - padding),
                                                                  height: max(0, size.height - padding)))
                    }
                    guard let start else { return }
                    let frame = WorktreeTextBoxResize.frame(origin: start.origin, size: start.size, handle: handle,
                                                           translation: value.translation, zoom: zoom,
                                                           minimumHeight: minimumHeight)
                    board.update(item.id) { $0.origin = frame.origin; $0.size = frame.size }
                }
                .onEnded { _ in
                    start = nil
                    withAnimation(.easeOut(duration: 0.3)) { press.point = nil } completion: { press.glow = 0 }
                    board.endHistoryAction()
                })
            .accessibilityLabel(item.isHeading ? "Resize heading" : "Resize text box")
    }
}
