import SwiftUI

struct ArticleView: View {
    let article: Article
    var namespace: Namespace.ID

    @State private var isLiked = false
    @State private var isBookmarked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Same placeholder as the feed, so the zoom reads as it growing into place.
                ArticleHeroPlaceholder(tint: article.tint)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: ArticleMetrics.heroCornerRadius))
                    // Keeps the square from filling wide windows.
                    .frame(maxWidth: ArticleMetrics.heroMaxWidth)
                    .frame(maxWidth: .infinity)

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
        // The home screen's shader, lit with this article's colors.
        .background {
            AmbientGradientBackground(palettes: [article.palette], progress: 0)
        }
        // Part of the page, not the navigation bar, so the buttons follow the zoom.
        .safeAreaBar(edge: .top) {
            ArticleTopBar(article: article)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: article.id, in: namespace))
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        ArticleView(article: .placeholder(number: 1, tint: .green, palette: .meadowLight), namespace: namespace)
    }
}
