import SwiftUI

/// Draws the white bloom over the flattened code: growing tiles clipped to
/// the card's continuous rounded shape, then the solid card.
struct BloomCanvas: View {
    let plan: BloomPlan
    /// Seconds since the bloom began.
    let time: Double
    let card: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        Canvas { context, _ in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: card)
            guard time < BloomPlan.duration else {
                context.fill(shape, with: .color(.white))
                return
            }
            context.clip(to: shape)
            // One path and one fill: the tiles all wind the same way, so the
            // non-zero rule fills their union.
            var tiles = Path()
            tiles.addRects(plan.tiles(in: card, at: time))
            context.fill(tiles, with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}
