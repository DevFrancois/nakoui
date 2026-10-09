import CoreGraphics

/// The color to draw for one pager position. A frame is a pure function of
/// that position, so interrupted and reversed swipes retrace the same colors
/// without a second animation clock. Ported from ZoomInUIKit's `GridGradientFrame`.
struct AmbientGradientFrame: Equatable {
    let palette: AmbientGradientPalette
    let bloom: Float

    /// How far down the wash reaches, as a fraction of the height. Mid-swipe,
    /// it reaches a little further.
    var reach: CGFloat {
        1 + CGFloat(min(max(bloom, 0), 1)) * 0.12
    }

    static func sample(
        palettes: [AmbientGradientPalette],
        progress: CGFloat,
        reduceMotion: Bool
    ) -> AmbientGradientFrame {
        guard !palettes.isEmpty else {
            return AmbientGradientFrame(palette: .lavenderHealth, bloom: 0)
        }
        let position = clampedProgress(progress, paletteCount: palettes.count)
        let lowerIndex = Int(position)
        let fraction = Float(position - CGFloat(lowerIndex))
        let from = palettes[lowerIndex]
        guard fraction > 0, lowerIndex + 1 < palettes.count else {
            return AmbientGradientFrame(palette: from, bloom: 0)
        }
        let to = palettes[lowerIndex + 1]
        // Quintic smootherstep has zero velocity and acceleration at page edges.
        let p = fraction
        let amount = min(1, max(0, p * p * p * (p * (6 * p - 15) + 10)))
        let palette = AmbientGradientPalette(
            light: from.light + (to.light - from.light) * amount,
            dark: from.dark + (to.dark - from.dark) * amount
        )
        let bloom = reduceMotion ? 0 : 16 * p * p * (1 - p) * (1 - p)
        return AmbientGradientFrame(palette: palette, bloom: bloom)
    }

    static func clampedProgress(_ progress: CGFloat, paletteCount: Int) -> CGFloat {
        guard !progress.isNaN else { return 0 }
        return min(max(progress, 0), CGFloat(max(paletteCount - 1, 0)))
    }
}
