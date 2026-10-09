import SwiftUI

/// The page color, with one color washing down from the top of the screen.
/// Each tab has its own color, and they crossfade as the pager moves.
struct AmbientGradientBackground: View {
    let palettes: [AmbientGradientPalette]
    /// Fractional index into `palettes`.
    let progress: CGFloat

    /// The wash's opacity down the screen: nearly straight to a fifth at
    /// mid-height, then a long tail that settles into the page.
    private static let falloff: [(location: CGFloat, opacity: Double)] = [
        (0, 1), (0.15, 0.78), (0.3, 0.56), (0.4, 0.4),
        (0.5, 0.22), (0.6, 0.13), (0.7, 0.065), (0.85, 0)
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let frame = AmbientGradientFrame.sample(palettes: palettes, progress: progress, reduceMotion: reduceMotion)
        let tone = colorScheme == .dark ? frame.palette.dark : frame.palette.light
        let color = Color(.sRGB, red: Double(tone.x), green: Double(tone.y), blue: Double(tone.z))
        // Mid-swipe, the wash reaches a little further down.
        let reach = 1 + CGFloat(min(max(frame.bloom, 0), 1)) * 0.12

        LinearGradient(
            stops: Self.falloff.map { Gradient.Stop(color: color.opacity($0.opacity), location: $0.location) },
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: reach)
        )
        .background(Color(.pageBackground))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // The pager supplies every frame. SwiftUI must not interpolate on its
        // own, or keep rendering after paging settles.
        .transaction { $0.animation = nil }
    }
}
