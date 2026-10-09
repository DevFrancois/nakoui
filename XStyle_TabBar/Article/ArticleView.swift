import SwiftUI

struct ArticleView: View {
    let article: Article
    var namespace: Namespace.ID

    @State private var isLiked = false
    @State private var isBookmarked = false
    /// Nil until the hero image has been sampled.
    @State private var backdrop: ArticleBackdrop?

    @Environment(\.colorScheme) private var colorScheme

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
            if let backdrop {
                ArticleBackdropView(backdrop: backdrop)
            } else {
                Rectangle()
                    .fill(.background)
                    .ignoresSafeArea()
            }
        }
        // Part of the page, not the navigation bar, so the buttons follow the zoom.
        .safeAreaBar(edge: .top) {
            ArticleTopBar(article: article)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: article.id, in: namespace))
        // The backdrop is toned to match the appearance, so text keeps its contrast.
        .onChange(of: colorScheme, initial: true) {
            sampleHero()
        }
    }

    /// Takes the backdrop's colors from the hero image, as it is shown.
    private func sampleHero() {
        backdrop = ArticleBackdrop(
            rendering: ArticleHeroImage(image: article.image),
            tone: colorScheme == .dark ? .dark : .light
        )
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        ArticleView(article: .placeholder(number: 1, tint: .green), namespace: namespace)
    }
}
