import SwiftUI

/// Bridges the custom UIKit glass menu to the root tab selection.
struct GlassTabBar: UIViewRepresentable {
    @Binding var selection: RootTab
    let axis: Axis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    @Environment(\.tabBarReflectionSource) private var reflectionSource
    #if DEBUG
    @Environment(\.tabBarReflectionTuning) private var reflectionTuning
    #endif
    @ScaledMetric(relativeTo: .body) private var height = 60.0

    func makeUIView(context: Context) -> GlassTabBarView {
        GlassTabBarView()
    }

    func updateUIView(_ view: GlassTabBarView, context: Context) {
        view.onSelect = { selection = $0 }
        view.reflectionSource = reflectionSource
        #if DEBUG
        view.reflectionSettings = reflectionTuning?.settings ?? .defaults
        #else
        view.reflectionSettings = .defaults
        #endif
        // The temporary Carousel preview has an intentionally light canvas,
        // including in Dark Mode. Its menu needs matching readable controls.
        let style: UIUserInterfaceStyle = selection == .search ? .light : .unspecified
        if view.overrideUserInterfaceStyle != style {
            view.overrideUserInterfaceStyle = style
        }
        let direction: UISemanticContentAttribute = layoutDirection == .rightToLeft
            ? .forceRightToLeft : .forceLeftToRight
        if view.semanticContentAttribute != direction {
            view.semanticContentAttribute = direction
        }
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
