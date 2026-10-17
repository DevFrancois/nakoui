import SwiftUI

struct ArticleGalleryPanel: View {
    let images: [ImageResource]
    @Binding var position: CGFloat

    var body: some View {
        ArticleGallery(images: images, position: $position)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: ArticleMetrics.heroCornerRadius))
    }
}
