import SwiftUI

/// Bridges the custom UIKit glass menu to the root tab selection.
struct GlassTabBar: UIViewRepresentable {
    @Binding var selection: RootTab
    let axis: Axis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var height = 60.0

    func makeUIView(context: Context) -> GlassTabBarView {
        GlassTabBarView()
    }

    func updateUIView(_ view: GlassTabBarView, context: Context) {
        view.onSelect = { selection = $0 }
        view.semanticContentAttribute = layoutDirection == .rightToLeft
            ? .forceRightToLeft : .forceLeftToRight
        view.update(
            selection: selection,
            axis: axis,
            locale: locale,
            animated: !reduceMotion && !context.transaction.disablesAnimations
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlassTabBarView, context: Context) -> CGSize? {
        GlassTabBarLayout.fittingSize(
            proposal: proposal,
            axis: axis,
            itemCount: RootTab.allCases.count,
            horizontalHeight: min(height, 84)
        )
    }
}
