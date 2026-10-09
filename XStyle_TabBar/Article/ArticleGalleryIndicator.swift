import SwiftUI

/// Page dots for the article gallery, on a Liquid Glass capsule so they stay
/// readable over any image.
struct ArticleGalleryIndicator: View {
    let count: Int
    let position: CGFloat

    private var page: Int {
        min(max(Int(position.rounded()), 0), count - 1)
    }

    var body: some View {
        HStack(spacing: ArticleMetrics.galleryDotSpacing) {
            ForEach(0..<count, id: \.self) { index in
                // The current page stretches, so it reads by shape as well as
                // color: glass mutes the dots' contrast over bright images.
                Capsule()
                    .fill(index == page ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(
                        width: index == page ? ArticleMetrics.galleryCurrentDotWidth : ArticleMetrics.galleryDotSize,
                        height: ArticleMetrics.galleryDotSize
                    )
            }
        }
        .padding(ArticleMetrics.galleryIndicatorPadding)
        .glassEffect(in: .capsule)
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Image \(page + 1) of \(count)"))
    }
}

#Preview {
    ArticleGalleryIndicator(count: 3, position: 1)
        .padding()
        .background(.green)
}
