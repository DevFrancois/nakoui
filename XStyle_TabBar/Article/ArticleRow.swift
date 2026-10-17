import SwiftUI

/// A feed post with an image, opening its article. Only the image is the zoom
/// source, so the transition grows it into the article's hero.
struct ArticleRow: View {
    let article: Article
    let namespace: Namespace.ID
    var settledWidth: CGFloat? = nil

    private static let avatarWidth: CGFloat = 44
    private static let avatarSpacing: CGFloat = 8

    var body: some View {
        let textWidth = settledWidth.map {
            max(0, $0 - 2 * FeedLayoutMetrics.horizontalPadding - Self.avatarWidth - Self.avatarSpacing)
        }

        NavigationLink(value: article) {
            HStack(alignment: .top, spacing: Self.avatarSpacing) {
                Circle()
                    .fill(article.tint.tertiary)
                    .frame(width: Self.avatarWidth, height: Self.avatarWidth)

                VStack(alignment: .leading, spacing: 8) {
                    SettledWidthLayout(width: textWidth) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(article.title)
                                .font(.headline)

                            Text(article.summary)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    ArticleHeroImage(image: article.image)
                        .frame(height: ArticleMetrics.thumbnailHeight)
                        .overlay(alignment: .topTrailing) {
                            if article.images.count > 1 {
                                ArticleImageCountBadge(count: article.images.count)
                                    .padding(ArticleMetrics.galleryIndicatorPadding)
                            }
                        }
                        .clipShape(.rect(cornerRadius: ArticleMetrics.thumbnailCornerRadius))
                        .matchedTransitionSource(id: article.id, in: namespace) { source in
                            source.clipShape(.rect(cornerRadius: ArticleMetrics.thumbnailCornerRadius))
                        }
                }
            }
            .padding(FeedLayoutMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
