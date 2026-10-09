import SwiftUI

/// A capsule filling a fraction of the width from the leading edge, growing
/// smoothly as the fraction animates.
@Animatable
nonisolated struct HigherLowerMeterFill: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        // Never narrower than it is tall, so the ends stay round.
        let width = max(rect.width * min(fraction, 1), rect.height)
        return Capsule().path(in: CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
    }
}
