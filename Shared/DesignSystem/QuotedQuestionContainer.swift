import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared iPhone/Mac quotation layout. Only punctuation takes space; the editor
/// retains its intrinsic width, bounded by the complete quoted container's limit.
struct QuotedQuestionContainer<Content: View>: View {
    static var centeredMaxWidth: CGFloat { 321 }
    static var quotedMaxWidth: CGFloat { 285 }

    let isEmpty: Bool
    let lineHeight: CGFloat
    let fontName: String
    var maximumWidth: CGFloat = Self.quotedMaxWidth
    var alignment: Alignment = .trailing
    var isPageDeparting = false
    /// Animate the marks to a new width even when emptiness is unchanged (recalled questions).
    var glidesMarks = false
    var onTapToFocus: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var coordinateSpace
    @State private var openingX: CGFloat = 0
    @State private var openingY: CGFloat = 0
    @State private var closingX: CGFloat = 0
    @State private var closingY: CGFloat = 0
    @State private var measuredIsEmpty: Bool?
    @State private var animatesWidth = false
    @State private var animatesHeight = false

    var body: some View {
        content()
            .padding(.horizontal, quotationWidth + quotationGap)
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named(coordinateSpace))
            } action: { bounds in
                guard !isPageDeparting else { return }
                animatesWidth = measuredIsEmpty != nil && (measuredIsEmpty != isEmpty || glidesMarks) && !reduceMotion
                animatesHeight = measuredIsEmpty != nil && !reduceMotion
                openingX = bounds.minX + quotationWidth / 2
                openingY = bounds.minY + lineHeight / 2
                closingX = bounds.maxX - quotationWidth / 2
                closingY = bounds.maxY - lineHeight / 2
                measuredIsEmpty = isEmpty
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapToFocus?() }
            .frame(maxWidth: maximumWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: alignment)
            .overlay {
                positionedMark("“", x: openingX, y: openingY)
                positionedMark("”", x: closingX, y: closingY)
            }
            .coordinateSpace(name: coordinateSpace)
    }

    private var quotationGap: CGFloat {
        AngroveTheme.Spacing.unit / (isEmpty ? 4 : 2)
    }

    private var quotationWidth: CGFloat {
        guard isEmpty else { return lineHeight * 0.5 }
        #if os(macOS)
        let font = NSFont(name: fontName, size: lineHeight * 1.12) ?? NSFont.systemFont(ofSize: lineHeight * 1.12)
        #else
        let font = UIFont(name: fontName, size: lineHeight * 1.12) ?? UIFont.systemFont(ofSize: lineHeight * 1.12)
        #endif
        let opening = ("“" as NSString).size(withAttributes: [.font: font]).width
        let closing = ("”" as NSString).size(withAttributes: [.font: font]).width
        return min(lineHeight * 0.5, ceil(max(opening, closing)))
    }

    /// Typing updates horizontal placement immediately; wrapping animates vertically.
    private func positionedMark(_ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        Text(verbatim: symbol)
            .font(.custom(fontName, fixedSize: lineHeight * 1.12))
            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            .frame(width: quotationWidth, height: lineHeight)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .position(x: x, y: 0)
            .animation(animatesWidth ? .springCamera : nil, value: x)
            .offset(y: y)
            .animation(animatesHeight ? .springCamera : nil, value: y)
            .opacity(measuredIsEmpty == nil ? 0 : 1)
    }
}
