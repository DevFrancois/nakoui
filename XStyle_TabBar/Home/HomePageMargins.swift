import SwiftUI

/// For you narrows beside the rail as it arrives. Departing pages and the
/// other tabs retain their resting content width throughout their travel.
struct HomePageMargins: ViewModifier {
    let tab: AppTab
    let pager: PagerState
    let width: CGFloat
    let viewportInsets: EdgeInsets

    func body(content: Content) -> some View {
        let margins = contentMargins
        content
            .contentMargins(.horizontal, margins, for: .scrollContent)
            .contentMargins(.horizontal, margins, for: .scrollIndicators)
            // Geometry already follows the finger or the pager's animation.
            // A second animation would leave the content lagging behind it.
            .animation(nil, value: margins)
    }

    private var contentMargins: EdgeInsets {
        // Ordinary phones have no side rail and need not observe each frame.
        guard viewportInsets.leading > 0 || viewportInsets.trailing > 0 else { return EdgeInsets() }
        // The last settled tab remains the source for the entire tap or drag,
        // including a cancelled swipe. Leaving For you must not widen it.
        guard tab == .bookmarks, pager.selectedTab != .bookmarks else {
            return EdgeInsets(
                top: 0, leading: viewportInsets.leading,
                bottom: 0, trailing: viewportInsets.trailing
            )
        }
        // Distant taps visually travel one page. Use that displayed position,
        // rather than the offscreen layout position of the skipped pages.
        let travel = 1 + (pager.tapTransition?.offsetFactor ?? 0)
        let offset = (CGFloat(tab.index) - pager.progress) * width * travel
        return EdgeInsets(
            top: 0,
            leading: min(max(viewportInsets.leading - offset, 0), viewportInsets.leading),
            bottom: 0,
            trailing: min(max(viewportInsets.trailing + offset, 0), viewportInsets.trailing)
        )
    }
}
