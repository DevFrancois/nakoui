import SwiftUI

struct ArticleView: View {
    let article: Article
    var namespace: Namespace.ID

    @State private var isLiked = false
    @State private var isBookmarked = false
    @State private var backdrop = ArticleBackdrop.neutral

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Same image as the feed, so the zoom reads as it growing into place.
                ArticleHeroImage(image: article.image)
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
        .background {
            ArticleBackdropView(backdrop: backdrop)
        }
        // Part of the page, not the navigation bar, so the buttons follow the zoom.
        .safeAreaBar(edge: .top) {
            ArticleTopBar(article: article)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        // The backdrop is always dark, so the page always uses light text.
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: article.id, in: namespace))
        .onAppear(perform: sampleHero)
    }

    /// Takes the backdrop's colors from the hero image, as it is shown.
    private func sampleHero() {
        backdrop = ArticleBackdrop(rendering: ArticleHeroImage(image: article.image)) ?? .neutral
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        ArticleView(article: .placeholder(number: 1, tint: .green), namespace: namespace)
    }
}
