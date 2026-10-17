import SwiftUI

/// Continuous article layout for compact windows and the iOS 26 fallback.
/// Native ArrangementView owns posture adaptation on supported regular layouts.
struct ArticleLayout: Layout {
    var minimumReadingWidth: CGFloat
    var prefersStack: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let proposedWidth = proposal.width ?? ArticleMetrics.contentMaxWidth
        let width = proposedWidth.isFinite ? max(0, proposedWidth) : ArticleMetrics.contentMaxWidth
        let columns = columns(in: width)
        let gallery = subviews[0].sizeThatFits(.init(width: columns.gallery.width, height: nil))
        let reading = subviews[1].sizeThatFits(.init(width: columns.reading.width, height: nil))
        let height = columns.isStacked
            ? gallery.height + ArticleMetrics.columnSpacing + reading.height
            : max(gallery.height, reading.height)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let columns = columns(in: bounds.width)
        let galleryProposal = ProposedViewSize(width: columns.gallery.width, height: nil)
        let galleryHeight = subviews[0].sizeThatFits(galleryProposal).height
        subviews[0].place(
            at: CGPoint(x: bounds.minX + columns.gallery.minX, y: bounds.minY),
            anchor: .topLeading, proposal: galleryProposal
        )
        subviews[1].place(
            at: CGPoint(
                x: bounds.minX + columns.reading.minX,
                y: bounds.minY + (columns.isStacked ? galleryHeight + ArticleMetrics.columnSpacing : 0)
            ),
            anchor: .topLeading,
            proposal: .init(width: columns.reading.width, height: nil)
        )
    }

    private func columns(in width: CGFloat) -> ArticleColumns {
        ArticleColumns(
            width: width, minimumReadingWidth: minimumReadingWidth,
            prefersStack: prefersStack
        )
    }
}

/// Horizontal bounds shared by measurement and placement. SwiftUI mirrors the
/// resulting positions for RTL, as it does for its built-in layout containers.
struct ArticleColumns {
    let gallery: CGRect
    let reading: CGRect
    let isStacked: Bool

    init(width: CGFloat, minimumReadingWidth: CGFloat, prefersStack: Bool) {
        let available = max(0, width - 2 * ArticleMetrics.pageMargin)
        let contentWidth = min(available, ArticleMetrics.spreadMaxWidth)
        let origin = (width - contentWidth) / 2
        let spacing = ArticleMetrics.columnSpacing

        let fitsColumns = contentWidth >= ArticleMetrics.galleryMinimumWidth + spacing + minimumReadingWidth
        if !prefersStack, fitsColumns {
            let galleryWidth = min(ArticleMetrics.heroMaxWidth, max(
                ArticleMetrics.galleryMinimumWidth,
                min((contentWidth - spacing) * 0.42, contentWidth - spacing - minimumReadingWidth)
            ))
            gallery = CGRect(x: origin, y: 0, width: galleryWidth, height: 0)
            reading = CGRect(x: origin + galleryWidth + spacing, y: 0, width: contentWidth - galleryWidth - spacing, height: 0)
            isStacked = false
        } else {
            let readingWidth = min(available, ArticleMetrics.contentMaxWidth)
            let galleryWidth = min(readingWidth, ArticleMetrics.heroMaxWidth)
            gallery = CGRect(x: (width - galleryWidth) / 2, y: 0, width: galleryWidth, height: 0)
            reading = CGRect(x: (width - readingWidth) / 2, y: 0, width: readingWidth, height: 0)
            isStacked = true
        }
    }
}
