import SwiftUI

/// One tab's scrolling page: placeholder posts, or the quiz hub for the Quizz
/// tab. It scrolls beneath the top menu, under the pager's soft edge.
struct FeedPage: View {
    let tab: AppTab
    /// Clears the expanded menu. Fixed, rather than following the menu's
    /// height, so collapsing the menu never moves the content.
    let topInset: CGFloat
    /// Shared with the article and quiz destinations for the zoom transitions.
    let zoomNamespace: Namespace.ID

    @State private var presentedDestination: ForYouDestination?

    private static let postCount = 40

    var body: some View {
        // One vertical scroll view per page: the pager reads its offset to
        // collapse the logo row, so the quiz hub nests no scroll views of its own.
        ScrollView(.vertical) {
            Group {
                if tab == .quizz {
                    QuizHub(namespace: zoomNamespace)
                } else {
                    LazyVStack(spacing: 0) {
                        if tab == .bookmarks {
                            WhatsNewRow(tint: tab.tint) { presentedDestination = .whatsNew }

                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    tile(.first)
                                    tile(.second)
                                }

                                HStack(spacing: 12) {
                                    tile(.third, size: .compact)
                                    tile(.fourth, size: .compact)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }

                        ForEach(1...Self.postCount, id: \.self) { number in
                            if tab == .articles {
                                ArticleRow(article: .placeholder(number: number, tint: tab.tint), namespace: zoomNamespace)
                            } else {
                                FeedRow(tab: tab, number: number)
                            }
                        }
                    }
                }
            }
            .padding(.top, TopMenuMetrics.contentTopPadding)
        }
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, topInset, for: .scrollContent)
        .contentMargins(.top, topInset, for: .scrollIndicators)
        .sheet(item: $presentedDestination, content: ForYouDetailSheet.init)
        // A tap on a card, not the sheet's dismissal.
        .sensoryFeedback(trigger: presentedDestination) { _, newValue in
            newValue == nil ? nil : .impact(flexibility: .soft)
        }
    }

    private func tile(_ destination: ForYouDestination, size: FeedTileSize = .regular) -> some View {
        FeedTile(caption: "Placeholder caption", title: destination.title, tint: destination.tint, size: size) {
            presentedDestination = destination
        }
    }
}
