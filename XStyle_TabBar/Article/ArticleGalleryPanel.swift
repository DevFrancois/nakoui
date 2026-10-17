import SwiftUI

struct ArticleGalleryPanel: View {
    let images: [ImageResource]
    @Binding var position: CGFloat
    @Binding var selectedImage: ImageResource?

    var body: some View {
        ArticleGallery(images: images, position: $position, selectedImage: $selectedImage)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: ArticleMetrics.heroCornerRadius))
            // Resolve the resizing card before laying out its paging contents.
            .geometryGroup()
    }
}
