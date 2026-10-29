import Foundation

/// Whether holding a tab opens its quick switch menu, set on the Profile
/// page, and how the menu shows, set on the Search page.
enum TabQuickSwitchSettings {
    static let enabledKey = "tabBar.quickSwitch.enabled"
    static let layoutKey = "tabBar.quickSwitch.layout"
    /// How long, in seconds, a tab is held before its menu opens.
    static let holdDurationKey = "tabBar.quickSwitch.holdDuration"
    /// Debug tuning for the spotlight's movement and resizing, in seconds.
    static let spotlightAnimationDurationKey = "tabBar.quickSwitch.spotlightAnimationDuration"
    static let listSwitchStyleKey = "tabBar.quickSwitch.listSwitchStyle"
    static let listEntranceStyleKey = "tabBar.quickSwitch.listEntranceStyle"
    static let listSwitchDurationKey = "tabBar.quickSwitch.listSwitchDuration"
    static let listEntranceDurationKey = "tabBar.quickSwitch.listEntranceDuration"
    static let defaultEnabled = true
    static let defaultHoldDuration = GlassTabBarMotion.calm.quickSwitchHoldDuration
    static let holdDurationRange: ClosedRange<Double> = 0.2...1.0
    static let holdDurationStep = 0.05
    static let defaultSpotlightDuration = 0.45
    static let spotlightDurationRange: ClosedRange<Double> = 0.1...1.5
    static let spotlightDurationStep = 0.05
    static let listDurationRange: ClosedRange<Double> = 0.1...1.5
    static let listDurationStep = 0.05

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.optionalBool(forKey: enabledKey) ?? defaultEnabled
    }

    /// A stored hold time within the range the setting offers.
    static func clampedHoldDuration(_ duration: Double) -> Double {
        guard duration.isFinite else { return defaultHoldDuration }
        return min(max(duration, holdDurationRange.lowerBound), holdDurationRange.upperBound)
    }

    static func clampedSpotlightDuration(_ duration: Double) -> Double {
        guard duration.isFinite else { return defaultSpotlightDuration }
        return min(max(duration, spotlightDurationRange.lowerBound), spotlightDurationRange.upperBound)
    }

    /// Stored debug tuning. Release rendering always uses the default.
    static func spotlightDuration(in defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.object(forKey: spotlightAnimationDurationKey) as? NSNumber
        return clampedSpotlightDuration(stored?.doubleValue ?? defaultSpotlightDuration)
    }

    static func clampedListSwitchDuration(_ duration: Double) -> Double {
        guard duration.isFinite else { return TabQuickSwitchListAnimationSettings.defaults.switchDuration }
        return min(max(duration, listDurationRange.lowerBound), listDurationRange.upperBound)
    }

    static func clampedListEntranceDuration(_ duration: Double) -> Double {
        guard duration.isFinite else { return TabQuickSwitchListAnimationSettings.defaults.entranceDuration }
        return min(max(duration, listDurationRange.lowerBound), listDurationRange.upperBound)
    }

    /// Rendering reads debug tuning through this factory. Release builds keep
    /// the shipped appearance even if a previous debug build saved overrides.
    static func listAnimationSettings(in defaults: UserDefaults = .standard) -> TabQuickSwitchListAnimationSettings {
        #if DEBUG
        let fallback = TabQuickSwitchListAnimationSettings.defaults
        return TabQuickSwitchListAnimationSettings(
            switchStyle: defaults.string(forKey: listSwitchStyleKey)
                .flatMap(TabQuickSwitchListSwitchStyle.init(rawValue:)) ?? fallback.switchStyle,
            entranceStyle: defaults.string(forKey: listEntranceStyleKey)
                .flatMap(TabQuickSwitchListEntranceStyle.init(rawValue:)) ?? fallback.entranceStyle,
            switchDuration: clampedListSwitchDuration(
                (defaults.object(forKey: listSwitchDurationKey) as? NSNumber)?.doubleValue ?? fallback.switchDuration),
            entranceDuration: clampedListEntranceDuration(
                (defaults.object(forKey: listEntranceDurationKey) as? NSNumber)?.doubleValue ?? fallback.entranceDuration)
        )
        #else
        return .defaults
        #endif
    }

    /// Only animation tuning is reset; layout, hold time, and enablement stay
    /// under the user's control.
    static func resetAnimationSettings(in defaults: UserDefaults = .standard) {
        let animation = TabQuickSwitchListAnimationSettings.defaults
        defaults.set(animation.switchStyle.rawValue, forKey: listSwitchStyleKey)
        defaults.set(animation.entranceStyle.rawValue, forKey: listEntranceStyleKey)
        defaults.set(animation.switchDuration, forKey: listSwitchDurationKey)
        defaults.set(animation.entranceDuration, forKey: listEntranceDurationKey)
        defaults.set(defaultSpotlightDuration, forKey: spotlightAnimationDurationKey)
    }
}

/// A complete set of List animation inputs, captured by a menu presentation.
struct TabQuickSwitchListAnimationSettings: Equatable {
    var switchStyle: TabQuickSwitchListSwitchStyle
    var entranceStyle: TabQuickSwitchListEntranceStyle
    var switchDuration: TimeInterval
    var entranceDuration: TimeInterval

    static let defaults = Self(switchStyle: .movingCard, entranceStyle: .fade,
                               switchDuration: 0.25, entranceDuration: 0.15)
}

enum TabQuickSwitchListSwitchStyle: String, CaseIterable, Identifiable {
    case movingCard
    case sequentialFade
    case immediate

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .movingCard: "Moving card"
        case .sequentialFade: "Sequential fade"
        case .immediate: "Immediate"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .movingCard: "Move and resize one card when switching between tabs."
        case .sequentialFade: "Fade out the current menu before showing the next one."
        case .immediate: "Replace the menu immediately when reaching another tab."
        }
    }
}

enum TabQuickSwitchListEntranceStyle: String, CaseIterable, Identifiable {
    case fade
    case slide
    case scale

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .fade: "Fade"
        case .slide: "Slide"
        case .scale: "Scale"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .fade: "Fade the menu into view when opening it."
        case .slide: "Slide the menu out from the tab bar when opening it."
        case .scale: "Expand the menu into view when opening it."
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
