import SwiftUI

/// The tank the bubbles rise through. While a round plays, a `TimelineView`
/// redraws them every frame from the time alone; held still, or once the
/// round is over, they sit in a grid. The count-in floats on top before the
/// round starts.
struct BubblePopPlayArea: View {
    let board: BubblePopBoard
    /// Whether bubbles hold still in a grid, for Reduce Motion, VoiceOver or
    /// large text.
    let isStatic: Bool
    let tint: Color
    let pop: (BubblePopItem) -> Void

    @ScaledMetric(relativeTo: .footnote) private var bubbleSize = BubblePopMetrics.bubbleSize
    /// The height of the scroll view showing the quiz, less its top bar and
    /// safe areas.
    @State private var visibleHeight = 0.0
    @Namespace private var glassNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isFloating: Bool {
        !isStatic && !board.isOver
    }

    private var floatingHeight: Double {
        let limits = BubblePopMetrics.playAreaHeights
        return min(max(visibleHeight * BubblePopMetrics.playAreaFraction, limits.lowerBound), limits.upperBound)
    }

    var body: some View {
        GlassEffectContainer(spacing: BubblePopMetrics.glassBlendDistance) {
            TimelineView(.animation(paused: !isFloating || !board.isPlaying)) { context in
                BubblePopLayout(arrangement: arrangement(at: context.date), spacing: BubblePopMetrics.gridSpacing) {
                    ForEach(board.items) { item in
                        BubblePopBubble(
                            item: item,
                            status: board.status(of: item),
                            diameter: diameter(of: item),
                            isStatic: isStatic,
                            isLive: board.isPlaying,
                            shakes: board.taps(on: item),
                            namespace: glassNamespace
                        ) {
                            pop(item)
                        }
                        .layoutValue(key: BubblePopDriftKey.self, value: item.drift)
                    }
                }
            }
        }
        .padding(.horizontal, BubblePopMetrics.playAreaInset)
        // Floating bubbles rise in through the bottom edge and out through
        // the top, so only the grid keeps a margin there.
        .padding(.vertical, isFloating ? 0 : BubblePopMetrics.playAreaInset)
        .background {
            // Deeper toward the bottom, where the bubbles rise from.
            RoundedRectangle(cornerRadius: QuizMetrics.cardCornerRadius)
                .fill(LinearGradient(colors: [tint.opacity(0.04), tint.opacity(0.22)], startPoint: .top, endPoint: .bottom))
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .overlay(alignment: isStatic ? .top : .center) {
            if case .countingIn(let value) = board.phase {
                BubblePopCountIn(value: value, tint: tint)
                    .padding(BubblePopMetrics.playAreaInset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Bubbles"))
        .background {
            // Measures the scroll view's height without its top bar and safe
            // areas, which its full bounds would include, so the tank's
            // bottom doesn't drop below the fold on smaller phones.
            Color.clear
                .containerRelativeFrame(.vertical)
                .onGeometryChange(for: Double.self) { proxy in
                    Double(proxy.size.height)
                } action: { height in
                    visibleHeight = height
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func arrangement(at date: Date) -> BubblePopArrangement {
        if isFloating {
            .floating(elapsed: board.elapsed(at: date), speed: board.speed, height: floatingHeight)
        } else {
            .grid
        }
    }

    /// Each bubble's own size, a little smaller once settled into the
    /// verdict. Nil at accessibility text sizes, where words outgrow any
    /// circle that fits the screen, so each bubble fits its word instead.
    private func diameter(of item: BubblePopItem) -> Double? {
        guard !dynamicTypeSize.isAccessibilitySize else { return nil }
        let settled = board.isOver && !isStatic ? BubblePopMetrics.settledScale : 1
        return min(bubbleSize, BubblePopMetrics.maximumBubbleSize) * item.scale * settled
    }
}
