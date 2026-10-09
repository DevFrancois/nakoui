import SwiftUI

/// The article's images, paging sideways inside the rounded hero card. Reports
/// its fractional page, so the backdrop can follow a swipe as it happens.
struct ArticleGallery: View {
    let images: [ImageResource]
    /// The page shown, fractional mid-swipe: 1.5 is halfway from the second image to the third.
    @Binding var position: CGFloat

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                // A constant list, so positions are stable identities.
                ForEach(images.indices, id: \.self) { index in
                    ArticleHeroImage(image: images[index])
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollDisabled(images.count < 2)
        .onScrollGeometryChange(for: CGFloat.self, of: pagePosition) { _, newPosition in
            position = newPosition
        }
        .overlay(alignment: .bottom) {
            if images.count > 1 {
                ArticleGalleryIndicator(count: images.count, position: position)
                    .padding(.bottom)
            }
        }
    }

    private func pagePosition(_ geometry: ScrollGeometry) -> CGFloat {
        guard geometry.containerSize.width > 0 else { return 0 }
        return (geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width
    }
}

#Preview {
    @Previewable @State var position: CGFloat = 0

    ArticleGallery(images: [.pic2, .pic3, .pic4], position: $position)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: ArticleMetrics.heroCornerRadius))
        .padding()
}
