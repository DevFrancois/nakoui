import SwiftUI

/// How the tab bar moves under a finger and as it slides back. The defaults
/// keep it calm; `original` is how the bar itself moved before, to compare
/// against. The highlight always moves tab by tab.
struct GlassTabBarMotion: Equatable {
    /// The whole capsule grows while held, by up to `grow`.
    var grows = true
    var grow = 1.02
    /// How long the capsule takes to settle back once released.
    var settleDuration = 0.35
    /// The capsule overshoots and wobbles as it settles; off, it settles
    /// critically damped.
    var wobbles = false
    var wobbleDamping = 0.45
    /// The highlight slides from tab to tab on a snappy spring; off, it jumps.
    var highlightSlides = true
    var highlightDuration = 0.25
    var highlightBounce = 0.15
    /// The bar overshoots where it rests as it slides back up.
    var bounces = false
    var bounce = 0.3

    static let calm = GlassTabBarMotion()
    static let original = GlassTabBarMotion(grow: 1.04, wobbles: true, bounces: true)

    static let growRange = 1.0...1.08
    static let settleDurationRange = 0.15...0.8
    static let wobbleDampingRange = 0.2...0.95
    static let highlightDurationRange = 0.1...0.6
    static let highlightBounceRange = 0.0...0.4
    static let bounceRange = 0.0...0.5

    /// The most the capsule grows while held, before its room clamps it.
    var pressedScale: CGFloat { grows ? grow : 1 }
    var releaseDamping: Double { wobbles ? wobbleDamping : 1 }
    /// Nil while the highlight jumps between tabs.
    var highlightSpring: (duration: TimeInterval, bounce: Double)? {
        highlightSlides ? (highlightDuration, highlightBounce) : nil
    }
    var slideBounce: Double { bounces ? bounce : 0 }
}

#if DEBUG
/// The motion dials, stored so they survive relaunches, read and written as
/// one value. Release builds have no dials and use `GlassTabBarMotion.calm`.
@propertyWrapper
struct StoredGlassTabBarMotion: DynamicProperty {
    @AppStorage("tabBarMotion.grows") private var grows = GlassTabBarMotion.calm.grows
    @AppStorage("tabBarMotion.grow") private var grow = GlassTabBarMotion.calm.grow
    @AppStorage("tabBarMotion.settleDuration") private var settleDuration = GlassTabBarMotion.calm.settleDuration
    @AppStorage("tabBarMotion.wobbles") private var wobbles = GlassTabBarMotion.calm.wobbles
    @AppStorage("tabBarMotion.wobbleDamping") private var wobbleDamping = GlassTabBarMotion.calm.wobbleDamping
    @AppStorage("tabBarMotion.highlightSlides") private var highlightSlides = GlassTabBarMotion.calm.highlightSlides
    @AppStorage("tabBarMotion.highlightDuration") private var highlightDuration = GlassTabBarMotion.calm.highlightDuration
    @AppStorage("tabBarMotion.highlightBounce") private var highlightBounce = GlassTabBarMotion.calm.highlightBounce
    @AppStorage("tabBarMotion.bounces") private var bounces = GlassTabBarMotion.calm.bounces
    @AppStorage("tabBarMotion.bounce") private var bounce = GlassTabBarMotion.calm.bounce

    init() {}

    var wrappedValue: GlassTabBarMotion {
        get {
            GlassTabBarMotion(grows: grows, grow: grow, settleDuration: settleDuration, wobbles: wobbles,
                              wobbleDamping: wobbleDamping, highlightSlides: highlightSlides,
                              highlightDuration: highlightDuration, highlightBounce: highlightBounce,
                              bounces: bounces, bounce: bounce)
        }
        nonmutating set {
            // Only the dial that moved is written, so one slider doesn't
            // republish every other stored value.
            store(newValue.grows, in: _grows)
            store(newValue.grow, in: _grow)
            store(newValue.settleDuration, in: _settleDuration)
            store(newValue.wobbles, in: _wobbles)
            store(newValue.wobbleDamping, in: _wobbleDamping)
            store(newValue.highlightSlides, in: _highlightSlides)
            store(newValue.highlightDuration, in: _highlightDuration)
            store(newValue.highlightBounce, in: _highlightBounce)
            store(newValue.bounces, in: _bounces)
            store(newValue.bounce, in: _bounce)
        }
    }

    var projectedValue: Binding<GlassTabBarMotion> {
        Binding { wrappedValue } set: { wrappedValue = $0 }
    }

    private func store<Value: Equatable>(_ value: Value, in storage: AppStorage<Value>) {
        if storage.wrappedValue != value { storage.wrappedValue = value }
    }
}
#endif
