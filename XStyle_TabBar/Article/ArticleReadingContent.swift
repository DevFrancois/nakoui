import SwiftUI

/// Reading content shares article-owned state across split and continuous layouts.
struct ArticleReadingContent: View {
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let paragraphs: [ArticleParagraph]
    @Binding var isLiked: Bool
    @Binding var isBookmarked: Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .id(ArticleReadingPosition.title)

            Text(summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .id(ArticleReadingPosition.summary)

            ArticleActionBar(isLiked: $isLiked, isBookmarked: $isBookmarked)
                .id(ArticleReadingPosition.actions)

            Divider()

            ForEach(paragraphs) { paragraph in
                Text(paragraph.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .id(ArticleReadingPosition.paragraph(paragraph.id))
            }
        }
        .scrollTargetLayout()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

nonisolated enum ArticleReadingPosition: Hashable, Sendable {
    case title, summary, actions
    case paragraph(ArticleParagraph.ID)
}
