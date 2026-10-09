import SwiftUI

/// The home screen's ambient shader, lit with colors from the article's image
/// along the top and bottom of the page, over a base also taken from it.
struct ArticleBackdropView: View {
    let backdrop: ArticleBackdrop

    var body: some View {
        AmbientGradientSurface(
            topLights: backdrop.topLights,
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
