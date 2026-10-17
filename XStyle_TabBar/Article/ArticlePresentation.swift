import SwiftUI

/// The system owns posture changes in a split. Compact windows keep the whole
/// article in one continuous scroll view, with selection owned by ArticleView.
struct ArticlePresentation<Gallery: View, Reading: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumReadingWidth: CGFloat = 300

    @Binding var readingPosition: ScrollPosition
    @ViewBuilder let gallery: Gallery
    @ViewBuilder let reading: Reading

    var body: some View {
        if #available(iOS 27.1, *), horizontalSizeClass == .regular {
            ArticleSplitPresentation(readingPosition: $readingPosition, gallery: gallery, reading: reading)
        } else {
            ScrollView {
                ArticleLayout(
                    minimumReadingWidth: minimumReadingWidth,
                    prefersStack: horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
                ) {
                    gallery
                    reading
                }
                .padding(.vertical, ArticleMetrics.pageMargin)
            }
            .scrollPosition($readingPosition, anchor: .top)
        }
    }
}

@available(iOS 27.1, *)
private struct ArticleSplitPresentation<Gallery: View, Reading: View>: View {
    @Binding var readingPosition: ScrollPosition
    let gallery: Gallery
    let reading: Reading

    var body: some View {
        // The arrangement has a finite viewport. Scrolling belongs inside its
        // panes, so a fold cannot move columns within one shared scroll offset.
        ArrangementView {
            gallery
                .frame(maxWidth: ArticleMetrics.heroMaxWidth, maxHeight: ArticleMetrics.heroMaxWidth, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(ArticleMetrics.pageMargin)
        } secondary: {
            ScrollView {
                reading
                    .frame(maxWidth: ArticleMetrics.contentMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(ArticleMetrics.pageMargin)
            }
            .scrollPosition($readingPosition, anchor: .top)
        }
        // Either split axis is valid; the system follows the active fold rather
        // than hiding the reader when a horizontal-only split cannot fit.
        .arrangementViewStyle(.split.axes([.horizontal, .vertical]))
        .clipped()
    }
}
