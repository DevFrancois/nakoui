import SwiftUI

/// The page color with a pastel light at the top of the screen. Each tab has
/// its own palette, and they crossfade as the pager moves.
struct AmbientGradientBackground: View {
    let palettes: [AmbientGradientPalette]
    /// Fractional index into `palettes`.
    let progress: CGFloat

    /// ZoomInUIKit's Debug defaults: half strength, over the top three quarters.
    private static let strength = 0.5
    private static let verticalCoverage: CGFloat = 0.75

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.pageBackground)

            AmbientGradientSurface(
                frame: .sample(palettes: palettes, progress: progress, reduceMotion: reduceMotion),
                background: colorScheme == .dark
                    ? AmbientGradientPalette.darkBackground
                    : AmbientGradientPalette.lightBackground,
                verticalCoverage: Self.verticalCoverage
            )
            .opacity(Self.strength)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // The pager supplies every frame. SwiftUI must not interpolate on its
        // own, or keep rendering after paging settles.
        .transaction { $0.animation = nil }
    }
}
