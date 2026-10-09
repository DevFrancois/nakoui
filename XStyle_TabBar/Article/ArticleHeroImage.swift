import SwiftUI

/// The article's image, filling whatever frame it is given. Shown in the feed
/// and at the top of the article, so the zoom reads as it growing into place.
struct ArticleHeroImage: View {
    let image: ImageResource

    var body: some View {
        // The clear base takes the proposed frame, so the image fills and crops
        // to it rather than imposing its own size on the layout.
        Color.clear
            .overlay {
                Image(image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

#Preview {
    ArticleHeroImage(image: .pic1)
        .frame(height: 240)
}
