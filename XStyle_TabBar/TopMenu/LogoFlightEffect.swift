import SwiftUI

/// Shrinks and fades a logo-row item as the row collapses, rising as far as the
/// content has scrolled, so it stays under the finger. With Reduce Motion it
/// rises and fades without shrinking.
struct LogoFlightEffect: ViewModifier {
    /// How far the row has collapsed, in points.
    let distance: CGFloat
    let flight: LogoFlight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let progress = distance / TopMenuMetrics.logoRowHeight

        content
            .scaleEffect(reduceMotion ? 1 : 1 + (flight.scale - 1) * progress)
            .offset(y: -distance)
            .opacity(Double(1 - progress))
    }
}
