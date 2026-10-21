import SwiftUI
import UIKit

/// NavigationStack places this custom item in its managed toolbar, including
/// Duo's shared vertical region. The item supplies its own single glass surface.
struct GlassTabBarToolbar: ToolbarContent {
    @Binding var selection: RootTab
    @Binding var layoutAxis: NSLayoutConstraint.Axis
    /// Slides the bar off the bottom of the screen; see `GlassTabBar`.
    var isHidden = false
    var windowBottom: CGFloat = 0
    /// The bar's top edge in global space, measured where it rests: its slide
    /// and press are visual only.
    @Binding var top: CGFloat?

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if #available(iOS 27.1, *) {
            ToolbarItem(placement: .bottomBar) {
                reportingTop(of: AdaptiveGlassTabBar(selection: $selection, layoutAxis: $layoutAxis,
                                                     isHidden: isHidden, windowBottom: windowBottom, restingTop: top))
            }
            .axisBehavior(.verticalPreferred)
            .sharedBackgroundVisibility(.hidden)
            .contentMarginsRemoved()
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .bottomBar) {
                reportingTop(of: GlassTabBar(selection: $selection, isHidden: isHidden, windowBottom: windowBottom,
                                             restingTop: top))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
    }

    /// Reports where the bar rests while it shows. As its toolbar hides, the
    /// item is laid out elsewhere, which isn't where the bar comes back to.
    /// Coming back, the toolbar also zooms the item about its center, so the
    /// top is taken from the center, which the zoom leaves in place, less half
    /// the bar's own height.
    private func reportingTop(of bar: some View) -> some View {
        bar.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).midY - proxy.size.height / 2
        } action: { top in
            if !isHidden {
                self.top = top
            }
        }
    }
}

@available(iOS 27.1, *)
private struct AdaptiveGlassTabBar: View {
    @Binding var selection: RootTab
    @Binding var layoutAxis: NSLayoutConstraint.Axis
    let isHidden: Bool
    let windowBottom: CGFloat
    let restingTop: CGFloat?
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        GlassTabBar(selection: $selection, layoutAxis: verticalEdge == nil ? .horizontal : .vertical,
                    isHidden: isHidden, windowBottom: windowBottom, restingTop: restingTop)
            .onChange(of: verticalEdge == nil, initial: true) {
                layoutAxis = verticalEdge == nil ? .horizontal : .vertical
            }
    }
}

struct GlassTabBar: View {
    @Binding var selection: RootTab
    var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    /// Springs the bar down off the screen, or fades it with Reduce Motion,
    /// as its toolbar hides.
    var isHidden = false
    /// The window's bottom edge in global space, which the bar slides past.
    var windowBottom: CGFloat = 0
    /// The bar's top edge in global space where it rests, which it slides
    /// from and back to; see `GlassTabBarToolbar.top`.
    var restingTop: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation = GlassTabBarPresentation()

    /// While the Scan tab's sheet is up, with a result or the history, the bar
    /// makes way for it. The Duo's vertical rail stays.
    static func hidesForScanSheet(selection: RootTab, isSheetShown: Bool, layoutAxis: NSLayoutConstraint.Axis) -> Bool {
        selection == .scanner && isSheetShown && layoutAxis == .horizontal
    }

    var body: some View {
        GlassTabBarRepresentable(selection: $selection, layoutAxis: layoutAxis, presentation: presentation)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                // Keep native glass behind the controls so its foreground
                // treatment cannot change their explicitly assigned colors.
                GlassTabBarBackground()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scaleEffect(x: reduceMotion ? 1 : presentation.scale.width,
                         y: reduceMotion ? 1 : presentation.scale.height)
            // This anchor is outside the visual transform. Touch locations and
            // layout validation stay in the toolbar's unscaled coordinate space.
            .background {
                GlassTabBarCoordinateSpace(presentation: presentation)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, layoutAxis == .horizontal ? GlassTabBarMetrics.horizontalToolbarBottomPadding : 0)
            .visualEffect { [isHidden, windowBottom, restingTop, reduceMotion] content, proxy in
                // From where the bar rests, not where it's laid out: once its
                // toolbar hides, the item moves to the window's top, and a
                // slide measured from there would bring the bar back from far
                // below the screen, overshooting its place by tens of points.
                let top = restingTop ?? proxy.frame(in: .global).minY
                return content.offset(y: isHidden && !reduceMotion ? max(0, windowBottom - top) : 0)
            }
            .opacity(isHidden && reduceMotion ? 0 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.3), value: isHidden)
            .allowsHitTesting(!isHidden)
            .accessibilityHidden(isHidden)
    }
}

private struct GlassTabBarRepresentable: UIViewRepresentable {
    @Binding var selection: RootTab
    let layoutAxis: NSLayoutConstraint.Axis
    let presentation: GlassTabBarPresentation

    func makeUIView(context: Context) -> GlassTabBarView {
        GlassTabBarView(selection: selection, presentation: presentation)
    }

    func updateUIView(_ view: GlassTabBarView, context: Context) {
        // Replace the callback too, so it always writes to the current binding.
        view.onSelect = { selection = $0 }
        presentation.updateView {
            view.updateEnvironment(
                locale: context.environment.locale,
                contentSizeCategory: UIContentSizeCategory(context.environment.dynamicTypeSize),
                layoutDirection: context.environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight,
                layoutAxis: layoutAxis,
                reduceMotion: context.environment.accessibilityReduceMotion,
                isEnabled: context.environment.isEnabled
            )
            view.select(selection, animated: !context.transaction.disablesAnimations)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlassTabBarView, context: Context) -> CGSize? {
        // One measurement owns the controls, glass, and unscaled touch anchor.
        // A separate clamping frame could give those layers different widths.
        uiView.fittingSize(proposedWidth: proposal.width)
    }
}

/// The chosen material stays behind the controls to preserve their colors.
private struct GlassTabBarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var glass: Glass {
        colorScheme == .dark
            ? .clear.tint(Color(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255).opacity(0.9))
            : .regular
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(colorScheme == .dark ? 0.3 : 0))
            Color.clear
                .glassEffect(glass.interactive(false), in: .capsule)
        }
    }
}
