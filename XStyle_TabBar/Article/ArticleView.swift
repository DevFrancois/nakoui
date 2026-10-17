import SwiftUI

struct ArticleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let article: Article
    let namespace: Namespace.ID

    @ScaledMetric(relativeTo: .body) private var minimumReadingWidth: CGFloat = 300

    @State private var isLiked = false
    @State private var isBookmarked = false
    /// One per image, in order; empty until they have been sampled.
    @State private var backdrops: [ArticleBackdrop] = []
    /// The gallery's page, fractional mid-swipe.
    @State private var galleryPosition: CGFloat = 0
    @State private var readingPosition: ArticleReadingPosition?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ArticleLayout(
                    minimumReadingWidth: minimumReadingWidth,
                    prefersStack: dynamicTypeSize.isAccessibilitySize,
                    division: activeDivision(in: geometry)
                ) {
                    // The gallery and reading view remain in the same layout,
                    // including while a fold or window resize changes columns.
                    ArticleGalleryPanel(images: article.images, position: $galleryPosition)

                    ArticleReadingContent(
                        title: article.title, summary: article.summary, paragraphs: article.paragraphs,
                        isLiked: $isLiked, isBookmarked: $isBookmarked
                    )
                }
                .padding(.vertical, ArticleMetrics.pageMargin)
            }
            .scrollPosition(id: $readingPosition)
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

    private func activeDivision(in geometry: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division)
                .first { $0.frame.height > $0.frame.width }?.frame
        }
        return nil
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

#Preview("Wide article", traits: .fixedLayout(width: 1_024, height: 768)) {
    @Previewable @Namespace var namespace

    NavigationStack {
        ArticleView(article: .placeholder(number: 2, tint: .green), namespace: namespace)
    }
}

#Preview("Accessible article", traits: .fixedLayout(width: 736, height: 678)) {
    @Previewable @Namespace var namespace

    NavigationStack {
        ArticleView(article: .placeholder(number: 2, tint: .green), namespace: namespace)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
