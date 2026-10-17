import SwiftUI

/// The article's images, paging sideways inside the rounded hero card. Reports
/// its fractional page, so the backdrop can follow a swipe as it happens.
struct ArticleGallery: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let images: [ImageResource]
    /// The page shown, fractional mid-swipe: 1.5 is halfway from the second image to the third.
    @Binding var position: CGFloat
    /// Owned by the article so switching between a split and continuous layout
    /// keeps the selected image, even when the gallery changes containers.
    @Binding var selectedImage: ImageResource?

    private var displayedIndex: Int {
        min(max(Int(position.rounded()), 0), max(images.count - 1, 0))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(images, id: \.self) { image in
                    ArticleHeroImage(image: image)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // The image identity remains the scroll target when its width changes.
        .scrollPosition(id: $selectedImage)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Article images")
        .accessibilityValue(Text("Image \(displayedIndex + 1) of \(images.count)"))
        .accessibilityAdjustableAction(adjustImage)
    }

    private func pagePosition(_ geometry: ScrollGeometry) -> CGFloat {
        guard geometry.containerSize.width > 0 else { return 0 }
        return (geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width
    }

    private func adjustImage(_ direction: AccessibilityAdjustmentDirection) {
        let index: Int
        switch direction {
        case .increment: index = min(displayedIndex + 1, images.count - 1)
        case .decrement: index = max(displayedIndex - 1, 0)
        @unknown default: return
        }
        guard images.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            selectedImage = images[index]
        }
    }
}

#Preview {
    @Previewable @State var position: CGFloat = 0
    @Previewable @State var selectedImage: ImageResource?

    ArticleGallery(images: [.pic2, .pic3, .pic4], position: $position, selectedImage: $selectedImage)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: ArticleMetrics.heroCornerRadius))
        .padding()
}
