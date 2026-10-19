import SwiftUI
import UIKit

/// NavigationStack places this custom item in its managed toolbar, including
/// Duo's shared vertical region. The item supplies its own single glass surface.
struct GlassTabBarToolbar: ToolbarContent {
    @Binding var selection: RootTab
    @Binding var layoutAxis: NSLayoutConstraint.Axis

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if #available(iOS 27.1, *) {
            ToolbarItem(placement: .bottomBar) {
                AdaptiveGlassTabBar(selection: $selection, layoutAxis: $layoutAxis)
            }
            .axisBehavior(.verticalPreferred)
            .sharedBackgroundVisibility(.hidden)
            .contentMarginsRemoved()
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .bottomBar) {
                GlassTabBar(selection: $selection)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
    }
}

@available(iOS 27.1, *)
private struct AdaptiveGlassTabBar: View {
    @Binding var selection: RootTab
    @Binding var layoutAxis: NSLayoutConstraint.Axis
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        GlassTabBar(selection: $selection, layoutAxis: verticalEdge == nil ? .horizontal : .vertical)
            .onChange(of: verticalEdge == nil, initial: true) {
                layoutAxis = verticalEdge == nil ? .horizontal : .vertical
            }
    }
}

struct GlassTabBar: View {
    @Binding var selection: RootTab
    var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation = GlassTabBarPresentation()

    var body: some View {
        GlassTabBarRepresentable(selection: $selection, layoutAxis: layoutAxis, presentation: presentation)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(
                .regular.tint(colorScheme == .dark ? .black.opacity(0.50) : nil).interactive(false),
                in: .capsule
            )
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
