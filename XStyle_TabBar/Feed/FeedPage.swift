import SwiftUI

/// One tab's scrolling feed of placeholder posts. It scrolls beneath the top
/// menu, under the pager's soft edge.
struct FeedPage: View {
    let tab: AppTab
    /// Clears the expanded menu. Fixed, rather than following the menu's
    /// height, so collapsing the menu never moves the content.
    let topInset: CGFloat
    /// Shared with the article destination for the zoom transition.
    let articleNamespace: Namespace.ID

    private static let postCount = 40

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(1...Self.postCount, id: \.self) { number in
                    if tab == .articles {
                        ArticleRow(article: .placeholder(number: number, tint: tab.tint), namespace: articleNamespace)
                    } else {
                        FeedRow(tab: tab, number: number)
                    }
                }
            }
            .padding(.top, TopMenuMetrics.contentTopPadding)
        }
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, topInset, for: .scrollContent)
        .contentMargins(.top, topInset, for: .scrollIndicators)
    }
}
