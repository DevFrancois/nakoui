import Foundation

/// Whether holding a tab opens its quick switch menu, set on the Profile
/// page, and how the menu shows, set on the Search page.
enum TabQuickSwitchSettings {
    static let enabledKey = "tabBar.quickSwitch.enabled"
    static let haloKey = "tabBar.quickSwitch.halo"
    static let layoutKey = "tabBar.quickSwitch.layout"
    /// How long, in seconds, a tab is held before its menu opens.
    static let holdDurationKey = "tabBar.quickSwitch.holdDuration"
    static let defaultEnabled = true
    static let defaultHoldDuration = GlassTabBarMotion.calm.quickSwitchHoldDuration
    static let holdDurationRange: ClosedRange<Double> = 0.2...1.0
    static let holdDurationStep = 0.05

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.optionalBool(forKey: enabledKey) ?? defaultEnabled
    }

    /// A stored hold time within the range the setting offers.
    static func clampedHoldDuration(_ duration: Double) -> Double {
        guard duration.isFinite else { return defaultHoldDuration }
        return min(max(duration, holdDurationRange.lowerBound), holdDurationRange.upperBound)
    }
}

/// What draws the eye to the bar while a menu is open.
enum TabQuickSwitchHalo: String, CaseIterable, Identifiable {
    case spotlight
    case blurredSpotlight
    case glowRing

    static let defaultHalo = Self.spotlight

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .spotlight: "Spotlight"
        case .blurredSpotlight: "Blur"
        case .glowRing: "Glow"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .spotlight: "The screen dims around a round spotlight on the bar and its menu."
        case .blurredSpotlight: "The screen dims and blurs around a round spotlight on the bar and its menu."
        case .glowRing: "A soft glow rings the bar. The screen stays as it is."
        }
    }
}

/// How a menu lays its items out.
enum TabQuickSwitchLayout: String, CaseIterable, Identifiable {
    case list
    case bubbles

    static let defaultLayout = Self.list

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .list: "List"
        case .bubbles: "Bubbles"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .list: "A glass card above the tab, one row per item."
        case .bubbles: "Round bubbles fan out above the tab, named as the finger reaches them."
        }
    }
}
