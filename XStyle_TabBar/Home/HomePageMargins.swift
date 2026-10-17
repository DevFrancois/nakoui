import SwiftUI

/// For you narrows beside the rail as it arrives. Departing pages and the
/// other tabs retain their resting content width throughout their travel.
struct HomePageMargins: ViewModifier {
    let tab: AppTab
    let pager: PagerState
    let width: CGFloat
    let viewportInsets: EdgeInsets

    @State private var columnIsNarrower = false

    func body(content: Content) -> some View {
        let margins = contentMargins
        content
            .contentMargins(.horizontal, margins.insets, for: .scrollContent)
            .contentMargins(.horizontal, margins.insets, for: .scrollIndicators)
            // Content keeps the widths it measured at rest while it narrows.
            .environment(\.holdsSettledWidth, margins.followsPaging)
            // Geometry already follows the finger or the pager's animation.
            // A second animation would leave the content lagging behind it.
            // Inset changes from rotation or posture keep their animation.
            .transaction(value: margins.insets) { transaction in
                if margins.followsPaging { transaction.animation = nil }
            }
            .onPreferenceChange(FeedColumnIsNarrowerKey.self) { [binding = $columnIsNarrower] isNarrower in
                binding.wrappedValue = isNarrower
            }
    }

    private var contentMargins: (insets: EdgeInsets, followsPaging: Bool) {
        // Ordinary phones have no side rail and need not observe each frame.
        guard viewportInsets.leading > 0 || viewportInsets.trailing > 0 else { return (EdgeInsets(), false) }
        let restingInsets = EdgeInsets(
            top: 0, leading: viewportInsets.leading,
            bottom: 0, trailing: viewportInsets.trailing
        )
        // The last settled tab remains the source for the entire tap or drag,
        // including a cancelled swipe. Leaving For you must not widen it.
        guard tab == .bookmarks, pager.selectedTab != .bookmarks else { return (restingInsets, false) }
        // A readable column that stops short of the page never reaches the
        // rail, so narrowing would only slide it within its page.
        guard !columnIsNarrower else { return (restingInsets, false) }
        // Distant taps visually travel one page. Use that displayed position,
        // rather than the offscreen layout position of the skipped pages.
        let travel = 1 + (pager.tapTransition?.offsetFactor ?? 0)
        let offset = (CGFloat(tab.index) - pager.progress) * width * travel
        // Offscreen, For you keeps its resting width, so its content measures
        // that width for the next arrival.
        guard abs(offset) < width else { return (restingInsets, false) }
        let insets = EdgeInsets(
            top: 0,
            leading: min(max(viewportInsets.leading - offset, 0), viewportInsets.leading),
            bottom: 0,
            trailing: min(max(viewportInsets.trailing + offset, 0), viewportInsets.trailing)
        )
        return (insets, true)
    }
}
