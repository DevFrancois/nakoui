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
    /// Where the Scan symbol rests, in global space.
    var onScanOriginChange: ((CGPoint) -> Void)? = nil

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if #available(iOS 27.1, *) {
            ToolbarItem(placement: .bottomBar) {
                reportingTop(of: AdaptiveGlassTabBar(selection: $selection, layoutAxis: $layoutAxis,
                                                     isHidden: isHidden, windowBottom: windowBottom, restingTop: top,
                                                     onScanOriginChange: onScanOriginChange))
            }
            .axisBehavior(.verticalPreferred)
            .sharedBackgroundVisibility(.hidden)
            .contentMarginsRemoved()
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .bottomBar) {
                reportingTop(of: GlassTabBar(selection: $selection, isHidden: isHidden, windowBottom: windowBottom,
                                             restingTop: top, onScanOriginChange: onScanOriginChange))
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
    let onScanOriginChange: ((CGPoint) -> Void)?
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        GlassTabBar(selection: $selection, layoutAxis: verticalEdge == nil ? .horizontal : .vertical,
                    isHidden: isHidden, windowBottom: windowBottom, restingTop: restingTop,
                    onScanOriginChange: onScanOriginChange)
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
    /// Where the Scan symbol rests, in global space, while the bar shows.
    var onScanOriginChange: ((CGPoint) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation = GlassTabBarPresentation()
    /// The controls' frame in global space, without the press zoom.
    @State private var controlsFrame: CGRect?

    // Release builds have no dials, so they ignore any values a debug build
    // left stored.
    #if DEBUG
    @StoredGlassTabBarMotion private var motion: GlassTabBarMotion
    #else
    private let motion = GlassTabBarMotion.calm
    #endif

    /// While the Scan tab's sheet is up, with a result or the history, the bar
    /// makes way for it. The Duo's vertical rail stays.
    static func hidesForScanSheet(selection: RootTab, isSheetShown: Bool, layoutAxis: NSLayoutConstraint.Axis) -> Bool {
        selection == .scanner && isSheetShown && layoutAxis == .horizontal
    }

    var body: some View {
        GlassTabBarRepresentable(selection: $selection, layoutAxis: layoutAxis, motion: motion,
                                 presentation: presentation)
            // The vertical toolbar proposes its compact item width. Keep the
            // full capsule width in both Duo postures; the bottom bar can flex.
            .fixedSize(horizontal: layoutAxis == .vertical, vertical: true)
            .onGeometryChange(for: CGRect.self) { proxy in
                // The press zoom scales about the centre, which it leaves in
                // place: the resting frame is the centre and the laid-out size.
                let frame = proxy.frame(in: .global)
                return CGRect(x: frame.midX - proxy.size.width / 2, y: frame.midY - proxy.size.height / 2,
                              width: proxy.size.width, height: proxy.size.height)
            } action: { frame in
                controlsFrame = frame
                reportScanOrigin()
            }
            .onChange(of: presentation.scanSymbol) {
                reportScanOrigin()
            }
            .onChange(of: isHidden) {
                reportScanOrigin()
            }
            .background {
                // Keep native glass behind the controls so its foreground
                // treatment cannot change their explicitly assigned colors.
                GlassTabBarBackground()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scaleEffect(x: reduceMotion ? 1 : presentation.scale.width,
                         y: reduceMotion ? 1 : presentation.scale.height)
            // This anchor is outside the visual transform. Touch locations stay
            // in the toolbar's unscaled coordinate space, sliding with the bar.
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
            // Where the toolbar places the bar, outside its slide: a finger
            // held as the toolbar moves the bar elsewhere must not commit, but
            // the bar still settling after sliding back hasn't moved anywhere.
            .background {
                GlassTabBarPlacement(presentation: presentation)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .opacity(isHidden && reduceMotion ? 0 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: motion.slideBounce),
                       value: isHidden)
            .allowsHitTesting(!isHidden)
            .accessibilityHidden(isHidden)
    }

    /// Reports the Scan symbol where the controls laid it out. Hidden, the
    /// toolbar lays the bar out elsewhere, which isn't where it comes back to.
    private func reportScanOrigin() {
        guard !isHidden, let controlsFrame, let symbol = presentation.scanSymbol else { return }
        onScanOriginChange?(CGPoint(x: controlsFrame.minX + symbol.x * controlsFrame.width,
                                    y: controlsFrame.minY + symbol.y * controlsFrame.height))
    }
}

private struct GlassTabBarRepresentable: UIViewRepresentable {
    @Binding var selection: RootTab
    let layoutAxis: NSLayoutConstraint.Axis
    let motion: GlassTabBarMotion
    let presentation: GlassTabBarPresentation

    func makeUIView(context: Context) -> GlassTabBarView {
        GlassTabBarView(selection: selection, presentation: presentation)
    }

    func updateUIView(_ view: GlassTabBarView, context: Context) {
        // Replace the callback too, so it always writes to the current binding.
        view.onSelect = { selection = $0 }
        // Read at the next press or release, so a held finger keeps its motion.
        presentation.motion = motion
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
