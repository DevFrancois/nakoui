import SwiftUI

struct ArticleView: View {
    let article: Article
    var namespace: Namespace.ID

    @State private var isLiked = false
    @State private var isBookmarked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // Same placeholder as the card, so the zoom lands on it.
                ArticleHeroPlaceholder(tint: article.tint)
                    .containerRelativeFrame(.vertical) { length, _ in
                        length * ArticleMetrics.heroHeightFraction
                    }

                VStack(alignment: .leading, spacing: 16) {
                    Text(article.title)
                        .font(.largeTitle)
                        .bold()

                    Text(article.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    ArticleActionBar(isLiked: $isLiked, isBookmarked: $isBookmarked)

                    Divider()

                    Text(article.body)
                        .font(.body)
                }
                .padding()
            }
        }
        // Let the hero run under the status bar and the glass buttons.
        .ignoresSafeArea(edges: .top)
        .background(.background)
        // Part of the page, not the navigation bar, so they follow the zoom.
        .overlay(alignment: .top) {
            ArticleTopBar(article: article)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: article.id, in: namespace))
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        ArticleView(article: .placeholder(number: 1, tint: .green), namespace: namespace)
    }
}
