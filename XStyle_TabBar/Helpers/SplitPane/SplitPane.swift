import SwiftUI

/// Two panes in the style of SplitPaneKit (see `SplitPaneDrag` for its licence).
///
/// Stacked, the top pane fills what the bottom one leaves, and the bottom one
/// snaps between `breakpoints`, shares of the split's height. It's dragged by
/// its handle, its top edge, or anywhere on it, like a sheet: content marked
/// `splitPaneScrollable()` scrolls only once the pane is at its tallest, and
/// hands downward drags back to it at its top. Side by side, the trailing pane
/// takes a fixed share of the width and there's no handle. Unlike
/// SplitPaneKit, heights come from the measured size on every layout, so the
/// panes re-snap when the window resizes, and the shares are of the area
/// inside the safe area. Each pane
/// runs into the safe area on the screen edges it touches: the top pane's
/// content, such as a camera, and the bottom pane's background.
struct SplitPane<Top: View, Bottom: View, TopEffect: ViewModifier>: View {
    @Binding var breakpoint: SplitPaneBreakpoint
    let breakpoints: [SplitPaneBreakpoint]
    /// The trailing pane's share of the width side by side; nil stacks them.
    var sideBySideFraction: CGFloat?
    /// Applied to the top pane outside its clipping shape, such as an entrance.
    var topEffect: TopEffect
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    @State private var size = CGSize.zero
    /// How far the current drag has moved the bottom pane's edge down.
    @State private var dragDistance: CGFloat = 0
    /// The bottom pane's top edge in global space, where its drag strip starts.
    @State private var bottomPaneTop: CGFloat = 0
    /// The latest drag's start and whether it moves the pane, decided once at
    /// its first change, as SplitPaneKit decides in `gestureRecognizerShouldBegin`.
    /// The strip's edge moves up with the finger, so judging again later would
    /// drop an upward drag midway and leave the pane stuck.
    @State private var dragDecision: (start: CGPoint, isAccepted: Bool)?
    /// A finger is down on the handle or the bottom pane, accepted or not.
    @GestureState private var isTouching = false
    /// Whether the bottom pane's scrollable content is at its top.
    @State private var isContentAtTop = true

    private enum DragSource {
        case handle
        /// Anywhere on the bottom pane, sharing it with its content.
        case pane
    }

    var body: some View {
        let isSideBySide = sideBySideFraction != nil
        let layout = isSideBySide ? AnyLayout(HStackLayout(spacing: Self.gap)) : AnyLayout(VStackLayout(spacing: 0))

        layout {
            top
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(topShape(isSideBySide: isSideBySide))
                .modifier(topEffect)
                .ignoresSafeArea(edges: isSideBySide ? [.vertical, .leading] : [.top, .horizontal])

            if !isSideBySide {
                handle
            }

            bottom
                .environment(\.splitPaneScrollsContent, isSideBySide || (isAtTallest && !isDragging))
                .onPreferenceChange(SplitPaneContentAtTopKey.self) { isAtTop in
                    isContentAtTop = isAtTop
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: isSideBySide ? size.width * (sideBySideFraction ?? 0) : nil,
                       height: isSideBySide ? nil : bottomHeight)
                .background {
                    bottomShape(isSideBySide: isSideBySide)
                        .fill(Self.paneBackground)
                        .ignoresSafeArea(edges: isSideBySide ? [.vertical, .trailing] : [.bottom, .horizontal])
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minY
                } action: { top in
                    bottomPaneTop = top
                }
                // SplitPaneKit's pan on the whole pane, alongside the content
                // rather than over it, so taps, such as on a close button,
                // still land.
                .simultaneousGesture(drag(from: .pane), isEnabled: !isSideBySide)
        }
        .background(Self.background.ignoresSafeArea())
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            self.size = size
        }
        // Snap points set from outside, too, such as when content arrives.
        .animation(Self.spring, value: breakpoint)
        .sensoryFeedback(.impact(weight: .light), trigger: breakpoint)
        .onChange(of: isTouching) {
            // A cancelled drag gets no `onEnded`.
            if !isTouching, dragDistance != 0 {
                withAnimation(Self.spring) { dragDistance = 0 }
            }
        }
    }

    private var sortedBreakpoints: [SplitPaneBreakpoint] {
        breakpoints.sorted { $0.ratio < $1.ratio }
    }

    /// The bottom pane's height range between the first and last snap points.
    private var heightRange: ClosedRange<CGFloat> {
        let lowest = size.height * (sortedBreakpoints.first?.ratio ?? breakpoint.ratio)
        let highest = size.height * (sortedBreakpoints.last?.ratio ?? breakpoint.ratio)
        return lowest...max(lowest, highest)
    }

    private var isAtTallest: Bool {
        breakpoint == sortedBreakpoints.last
    }

    private var isDragging: Bool {
        isTouching && dragDecision?.isAccepted == true
    }

    private var restingHeight: CGFloat {
        size.height * breakpoint.ratio
    }

    private var bottomHeight: CGFloat {
        guard dragDistance != 0 else { return restingHeight }
        return SplitPaneDrag.rubberBanded(restingHeight - dragDistance, within: heightRange)
    }

    private var handle: some View {
        Capsule()
            .fill(Self.handleColor)
            .frame(width: Self.handleSize.width, height: Self.handleSize.height)
            .scaleEffect(isDragging ? 1.2 : 1)
            .opacity(isDragging ? 0.8 : 1)
            .animation(.easeOut(duration: 0.2), value: isDragging)
            .frame(maxWidth: .infinity)
            .frame(height: Self.gap)
            .contentShape(.rect)
            .gesture(drag(from: .handle))
            .accessibilityElement()
            .accessibilityLabel("Pane size")
            .accessibilityValue(Double(breakpoint.ratio).formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                let sorted = sortedBreakpoints
                guard let index = sorted.firstIndex(of: breakpoint) else { return }
                let next = switch direction {
                case .increment: min(index + 1, sorted.count - 1)
                case .decrement: max(index - 1, 0)
                @unknown default: index
                }
                withAnimation(Self.spring) { breakpoint = sorted[next] }
            }
    }

    /// In global space, so the translation stays steady as the pane under the
    /// finger moves. On the pane, a few points pass first, so the drag's
    /// direction is clear when it's judged.
    private func drag(from source: DragSource) -> some Gesture {
        DragGesture(minimumDistance: source == .pane ? 6 : 1, coordinateSpace: .global)
            .updating($isTouching) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard accepts(value, from: source) else { return }
                dragDistance = value.translation.height
            }
            .onEnded { value in
                guard accepts(value, from: source) else { return }
                let end = SplitPaneDrag.rubberBanded(restingHeight - value.translation.height, within: heightRange)
                let target = SplitPaneDrag.target(
                    from: breakpoint, in: breakpoints, startHeight: restingHeight, endHeight: end,
                    velocity: value.velocity.height, totalHeight: size.height
                )
                withAnimation(Self.spring) {
                    breakpoint = target
                    dragDistance = 0
                }
            }
    }

    /// Whether a drag moves the pane, judged at its first change, while the
    /// pane is still where the finger came down. A new drag has a new start.
    private func accepts(_ value: DragGesture.Value, from source: DragSource) -> Bool {
        if let dragDecision, dragDecision.start == value.startLocation {
            return dragDecision.isAccepted
        }
        let isAccepted = switch source {
        case .handle:
            true
        case .pane:
            SplitPaneDrag.movesPane(
                startsInStrip: value.startLocation.y - bottomPaneTop <= Self.dragStripHeight,
                isAtTallest: isAtTallest, isContentAtTop: isContentAtTop,
                isDownward: value.translation.height > 0
            )
        }
        dragDecision = (value.startLocation, isAccepted)
        return isAccepted
    }

    private func topShape(isSideBySide: Bool) -> UnevenRoundedRectangle {
        let radius = Self.cornerRadius
        return isSideBySide
            ? UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous)
            : UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
    }

    private func bottomShape(isSideBySide: Bool) -> UnevenRoundedRectangle {
        let radius = Self.cornerRadius
        return isSideBySide
            ? UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
    }

    // SplitPaneKit's defaults.
    private static var gap: CGFloat { 20 }
    private static var handleSize: CGSize { CGSize(width: 56, height: 4) }
    private static var cornerRadius: CGFloat { 40 }
    private static var dragStripHeight: CGFloat { 44 }
    /// 0.45 s with damping 0.7.
    private static var spring: Animation { .spring(duration: 0.45, bounce: 0.3) }
    private static var handleColor: Color { Color(uiColor: .label).opacity(0.08) }
    private static var background: Color { Color(uiColor: .systemGroupedBackground) }
    private static var paneBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
}

extension SplitPane where TopEffect == EmptyModifier {
    init(
        breakpoint: Binding<SplitPaneBreakpoint>, breakpoints: [SplitPaneBreakpoint], sideBySideFraction: CGFloat? = nil,
        @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom
    ) {
        self.init(breakpoint: breakpoint, breakpoints: breakpoints, sideBySideFraction: sideBySideFraction,
                  topEffect: EmptyModifier(), top: top, bottom: bottom)
    }
}

#Preview {
    @Previewable @State var breakpoint = SplitPaneBreakpoint.peek

    SplitPane(breakpoint: $breakpoint, breakpoints: [.peek, .half, .large]) {
        Color.black
    } bottom: {
        Text(breakpoint.name)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
