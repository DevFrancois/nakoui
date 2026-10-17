import SwiftUI

/// The Home tab's top menu, highlighting the committed destination. It reads
/// the pager itself, keeping selection updates out of `ContentView`.
struct HomeTopMenu<Leading: View>: View {
    let title: String
    let pager: PagerState
    let logoCollapse: LogoCollapse
    let onSelect: (AppTab) -> Void
    @ViewBuilder let leading: Leading

    var body: some View {
        TopMenuBar(
            title: title,
            selection: CGFloat(pager.highlightedTab.index),
            selectedTab: pager.highlightedTab,
            isSelectionLocked: true,
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
