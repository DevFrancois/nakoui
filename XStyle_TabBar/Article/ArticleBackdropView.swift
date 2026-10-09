import SwiftUI

/// The home screen's ambient shader, lit with colors from the article's image
/// and spread down the page over a dark base.
struct ArticleBackdropView: View {
    let backdrop: ArticleBackdrop

    var body: some View {
        AmbientGradientSurface(
            frame: AmbientGradientFrame(colors: backdrop.lights, bloom: 0),
            background: backdrop.base,
            verticalCoverage: ArticleMetrics.backdropCoverage
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
