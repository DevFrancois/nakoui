import SwiftUI

/// The Home tab's top menu, highlighting the chip under the pager. It reads
/// the pager itself, so a swipe redraws the menu and not `ContentView`.
struct HomeTopMenu<Leading: View>: View {
    let title: String
    let pager: PagerState
    let logoCollapse: LogoCollapse
    let onSelect: (AppTab) -> Void
    @ViewBuilder let leading: Leading

    var body: some View {
        TopMenuBar(
            title: title,
            selection: pager.lockedTab.map { CGFloat($0.index) } ?? pager.progress,
            selectedTab: pager.lockedTab ?? pager.selectedTab,
            isSelectionLocked: pager.lockedTab != nil,
            logoCollapse: logoCollapse,
            onSelect: onSelect
        ) {
            leading
        } trailing: {
            // Nothing on the right: search lives in the tab bar.
            EmptyView()
        }
    }
}
