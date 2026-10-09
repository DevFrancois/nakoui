import CoreGraphics

/// The colors to draw for one pager position. A frame is a pure function of
/// that position, so interrupted and reversed swipes retrace the same colors
/// without a second animation clock. Ported from ZoomInUIKit's `GridGradientFrame`.
struct AmbientGradientFrame: Equatable {
    let colors: [SIMD3<Float>]
    let bloom: Float

    static func sample(
        palettes: [AmbientGradientPalette],
        progress: CGFloat,
        reduceMotion: Bool
    ) -> AmbientGradientFrame {
        guard !palettes.isEmpty else {
            return AmbientGradientFrame(colors: AmbientGradientPalette.lavenderHealth.colors, bloom: 0)
        }
        let position = clampedProgress(progress, paletteCount: palettes.count)
        let lowerIndex = Int(position)
        let fraction = Float(position - CGFloat(lowerIndex))
        let from = palettes[lowerIndex].colors
        guard fraction > 0, lowerIndex + 1 < palettes.count else {
            return AmbientGradientFrame(colors: from, bloom: 0)
        }
        let to = palettes[lowerIndex + 1].colors
        // Quintic smootherstep has zero velocity and acceleration at page edges.
        let p = fraction
        let amount = min(1, max(0, p * p * p * (p * (6 * p - 15) + 10)))
        let colors = zip(from, to).map { $0 + ($1 - $0) * amount }
        let bloom = reduceMotion ? 0 : 16 * p * p * (1 - p) * (1 - p)
        return AmbientGradientFrame(colors: colors, bloom: bloom)
    }

    static func clampedProgress(_ progress: CGFloat, paletteCount: Int) -> CGFloat {
        guard !progress.isNaN else { return 0 }
        return min(max(progress, 0), CGFloat(max(paletteCount - 1, 0)))
    }
}
