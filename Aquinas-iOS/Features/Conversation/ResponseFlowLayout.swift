import SwiftUI

// MARK: - Streaming Text Helpers

/// Lightweight entrance effect for streamed words.
struct GlideFadeModifier: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 3 : 0)
            .opacity(isActive ? 0 : 1)
            .offset(y: isActive ? 14 : 0)
            .scaleEffect(isActive ? 0.95 : 1)
    }
}

/// Compatibility name for older response-card code.
typealias BlurFadeModifier = GlideFadeModifier

/// Simple wrapping layout for streamed words and inline insight links.
struct FlowLayout: Layout {
    /// Extra space between rows, on top of each row's text height. Plain text meant to read like
    /// a model response uses this as its `lineSpacing`.
    static let rowSpacing: CGFloat = 8

    var spacing: CGFloat = 4.5
    var alignment: TextAlignment = .center
    /// Stretches every wrapped row except the last to the full width by widening the word gaps.
    var justified = false

    // MARK: - Cache
    //
    // SwiftUI calls sizeThatFits + placeSubviews on every layout pass, and both
    // previously recreated a full FlowResult — measuring every word from scratch
    // each time. For a 500-word response streaming 4 words every 55 ms that
    // amounted to ~188,000 CoreText sizeThatFits calls before the stream finished.
    //
    // The fix: use SwiftUI's built-in Layout cache to remember completed words by
    // subview index. The trailing token is deliberately remeasured because a
    // stream chunk can still be extending it in place.
    //
    // Expected reduction: ~188,000 → ~1,000 total measurements for a 500-word stream.

    struct Cache {
        var sizes: [Int: CGSize] = [:]
        var subviewCount = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(subviewCount: subviews.count)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // A stream chunk can extend the current trailing token without adding
        // another subview ("res" -> "response"). Its index is unchanged, but its
        // measured width is not. Invalidate the previous trailing token whenever
        // SwiftUI updates the subviews so streamed glyphs never get placed inside
        // a stale, narrower measurement.
        let firstMutableIndex = max(
            0,
            min(cache.subviewCount, subviews.count) - 1
        )
        cache.sizes = cache.sizes.filter {
            $0.key < firstMutableIndex && $0.key < subviews.count
        }
        cache.subviewCount = subviews.count
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing, alignment: alignment, justified: justified, cache: &cache).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing, alignment: alignment, justified: justified, cache: &cache)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.points[index].x,
                            y: bounds.minY + result.points[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []

        init(
            in maxWidth: CGFloat,
            subviews: Subviews,
            spacing: CGFloat,
            alignment: TextAlignment,
            justified: Bool,
            cache: inout Cache
        ) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            // Track each row's subview range and packed width so we can center
            // every row horizontally once the full row is known.
            var rowRanges: [(range: Range<Int>, width: CGFloat)] = []
            var rowStart = 0

            for (idx, subview) in subviews.enumerated() {
                let wordSize: CGSize
                let isTrailingToken = idx == subviews.count - 1
                if !isTrailingToken, let hit = cache.sizes[idx] {
                    wordSize = hit
                } else {
                    wordSize = subview.sizeThatFits(.unspecified)
                    if !isTrailingToken {
                        cache.sizes[idx] = wordSize
                    }
                }

                if currentX + wordSize.width > maxWidth && currentX > 0 {
                    // Close the row that just ended (drop the trailing spacing).
                    rowRanges.append((rowStart..<idx, max(0, currentX - spacing)))
                    rowStart = idx
                    currentX = 0
                    currentY += lineHeight + FlowLayout.rowSpacing
                    lineHeight = 0
                }
                points.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, wordSize.height)
                currentX += wordSize.width + spacing
            }
            // Close the final row.
            rowRanges.append((rowStart..<subviews.count, max(0, currentX - spacing)))

            // Position each completed row using the user's response alignment.
            for (rowIndex, (range, width)) in rowRanges.enumerated() {
                if justified, rowIndex < rowRanges.count - 1, range.count > 1 {
                    let extraPerGap = max(0, maxWidth - width) / CGFloat(range.count - 1)
                    for i in range {
                        points[i].x += extraPerGap * CGFloat(i - range.lowerBound)
                    }
                    continue
                }
                let offset: CGFloat
                switch alignment {
                case .center:
                    offset = max(0, (maxWidth - width) / 2)
                default:
                    offset = 0
                }
                for i in range {
                    points[i].x += offset
                }
            }

            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// Shared transition shorthand.
extension AnyTransition {
    static var streamedTextFade: AnyTransition {
        .opacity.animation(.easeInOut(duration: 0.55))
    }

    static var glideFadeUp: AnyTransition {
        .modifier(active: GlideFadeModifier(isActive: true), identity: GlideFadeModifier(isActive: false))
        .animation(.easeOut(duration: 0.22))
    }

    static var blurSlideUp: AnyTransition {
        glideFadeUp
    }

    static var blurredTitleReplacement: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: GlideFadeModifier(isActive: true),
                identity: GlideFadeModifier(isActive: false)
            )
            .animation(.easeOut(duration: 0.5)),
            removal: .modifier(
                active: GlideFadeModifier(isActive: true),
                identity: GlideFadeModifier(isActive: false)
            )
            .animation(.easeInOut(duration: 0.5))
        )
    }
}
