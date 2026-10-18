import SwiftUI
import UIKit

/// Keeps the feed's asset pixels in a public image backing. Rendering a SwiftUI
/// proxy image into the reflection crop can otherwise rerasterize it every frame.
/// The gallery retains ArticleHeroImage, which also supports ImageRenderer.
struct ArticleThumbnailImage: View {
    let image: ImageResource

    var body: some View {
        Color.clear
            .overlay {
                AssetImageView(image: image)
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private struct AssetImageView: UIViewRepresentable {
        let image: ImageResource

        func makeUIView(context: Context) -> UIImageView {
            let view = UIImageView()
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            return view
        }

        func updateUIView(_ view: UIImageView, context: Context) {
            guard context.coordinator.image != image else { return }
            let uiImage = UIImage(resource: image)
            view.image = uiImage
            if let pixels = uiImage.cgImage {
                // Warm the same immutable source that the reflection capture
                // sees later. The shared cache schedules all decoding off-main.
                TabBarPreparedImageCache.shared.image(for: pixels, priority: .prewarm)
            }
            context.coordinator.image = image
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
            guard let width = proposal.width, let height = proposal.height,
                  width.isFinite, height.isFinite else { return nil }
            return CGSize(width: width, height: height)
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator {
            var image: ImageResource?
        }
    }
}
