import SwiftUI

/// The home screen's ambient shader, lit with colors from the article's image
/// along the top and bottom of the page, over a base also taken from it.
struct ArticleBackdropView: View {
    let backdrop: ArticleBackdrop

    var body: some View {
        AmbientGradientSurface(
            frame: AmbientGradientFrame(colors: backdrop.topLights, bloom: 0),
            background: backdrop.base,
            verticalCoverage: ArticleMetrics.backdropCoverage,
            bottomLights: backdrop.bottomLights,
            bottomCoverage: ArticleMetrics.backdropBottomCoverage
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
