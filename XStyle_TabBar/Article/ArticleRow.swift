import SwiftUI

/// A feed post with an image, opening its article. Only the image is the zoom
/// source, so the transition grows it into the article's hero.
struct ArticleRow: View {
    let article: Article
    let namespace: Namespace.ID

    var body: some View {
        NavigationLink(value: article) {
            HStack(alignment: .top) {
                Circle()
                    .fill(article.tint.tertiary)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.headline)

                    Text(article.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    ArticleHeroPlaceholder(tint: article.tint)
                        .frame(height: ArticleMetrics.thumbnailHeight)
                        .clipShape(.rect(cornerRadius: ArticleMetrics.thumbnailCornerRadius))
                        .matchedTransitionSource(id: article.id, in: namespace) { source in
                            source.clipShape(.rect(cornerRadius: ArticleMetrics.thumbnailCornerRadius))
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
