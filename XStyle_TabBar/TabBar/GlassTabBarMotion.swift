import Foundation

/// Controls the stepped highlight and the bar's return slide. Native
/// interactive glass handles the capsule's response to a press.
struct GlassTabBarMotion: Equatable {
    /// The highlight slides from tab to tab on a snappy spring; off, it jumps.
    var highlightSlides = true
    var highlightDuration = 0.25
    var highlightBounce = 0.15
    /// The bar overshoots where it rests as it slides back up.
    var bounces = false
    var bounce = 0.3

    static let calm = GlassTabBarMotion()

    /// Nil while the highlight jumps between tabs.
    var highlightSpring: (duration: TimeInterval, bounce: Double)? {
        highlightSlides ? (highlightDuration, highlightBounce) : nil
    }
    var slideBounce: Double { bounces ? bounce : 0 }
}
