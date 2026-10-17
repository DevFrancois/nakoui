import SwiftUI

struct ArticleView: View {
    let article: Article
    var namespace: Namespace.ID

    @State private var isLiked = false
    @State private var isBookmarked = false
    /// One per image, in order; empty until they have been sampled.
    @State private var backdrops: [ArticleBackdrop] = []
    /// The gallery's page, fractional mid-swipe.
    @State private var galleryPosition: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Opens on the feed's image, so the zoom reads as it growing into place.
                ArticleGallery(images: article.images, position: $galleryPosition)
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
            .frame(maxWidth: ArticleMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background {
            if let backdrop = ArticleBackdrop.blending(backdrops, at: galleryPosition) {
                ArticleBackdropView(backdrop: backdrop)
            } else {
                Rectangle()
                    .fill(.background)
                    .ignoresSafeArea()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // The system places Back and Share in the current navigation bar,
        // including Duo's vertical toolbar.
        .toolbar {
            ArticleToolbar(article: article)
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: article.id, in: namespace))
        // The backdrop is toned to match the appearance, so text keeps its contrast.
        .onChange(of: colorScheme, initial: true) {
            sampleImages()
        }
    }

    /// Takes a backdrop from each gallery image, as it is shown, so swiping
    /// can blend between them. All or nothing, to keep pages and backdrops aligned.
    private func sampleImages() {
        let tone: ArticleBackdrop.Tone = colorScheme == .dark ? .dark : .light
        let sampled = article.images.compactMap { image in
            ArticleBackdrop(rendering: ArticleHeroImage(image: image), tone: tone)
        }
        backdrops = sampled.count == article.images.count ? sampled : []
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        ArticleView(article: .placeholder(number: 1, tint: .green), namespace: namespace)
    }
}
