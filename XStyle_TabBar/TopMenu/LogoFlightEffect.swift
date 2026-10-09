import SwiftUI

/// Flies a logo-row item into the device pill as the row collapses, and back
/// as it returns. Each item scales about its own centre while it fades.
struct LogoFlightEffect: ViewModifier {
    let isVisible: Bool
    let flight: LogoFlight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isFlying = !isVisible && !reduceMotion

        content
            .scaleEffect(isFlying ? flight.scale : 1)
            .offset(y: isFlying ? flight.travel : 0)
            .opacity(isVisible ? 1 : 0)
            .animation(
                reduceMotion ? TopMenuMetrics.collapseAnimation : TopMenuMetrics.flightAnimation,
                value: isVisible
            )
    }
}
