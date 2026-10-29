import Foundation
import Testing
@testable import XStyle_TabBar

@MainActor
struct TabQuickSwitchListAnimationSettingsTests {
    @Test("List animation defaults use a moving card and a short fade entrance")
    func defaults() throws {
        let expected = TabQuickSwitchListAnimationSettings(switchStyle: .movingCard, entranceStyle: .fade,
                                                          switchDuration: 0.25, entranceDuration: 0.15)
        #expect(TabQuickSwitchListAnimationSettings.defaults == expected)
        try withDefaults { defaults, _ in
            #expect(TabQuickSwitchSettings.listAnimationSettings(in: defaults) == expected)
        }
    }

    @Test("Each List style and both durations persist independently",
          arguments: TabQuickSwitchListSwitchStyle.allCases, TabQuickSwitchListEntranceStyle.allCases)
    func persistence(switchStyle: TabQuickSwitchListSwitchStyle,
                     entranceStyle: TabQuickSwitchListEntranceStyle) throws {
        try withDefaults { defaults, name in
            defaults.set(switchStyle.rawValue, forKey: TabQuickSwitchSettings.listSwitchStyleKey)
            defaults.set(entranceStyle.rawValue, forKey: TabQuickSwitchSettings.listEntranceStyleKey)
            defaults.set(0.8, forKey: TabQuickSwitchSettings.listSwitchDurationKey)
            defaults.set(1.2, forKey: TabQuickSwitchSettings.listEntranceDurationKey)
            defaults.set(0.65, forKey: TabQuickSwitchSettings.spotlightAnimationDurationKey)
            let reopened = try #require(UserDefaults(suiteName: name))
            #if DEBUG
            #expect(TabQuickSwitchSettings.listAnimationSettings(in: reopened) ==
                    TabQuickSwitchListAnimationSettings(switchStyle: switchStyle, entranceStyle: entranceStyle,
                                                       switchDuration: 0.8, entranceDuration: 1.2))
            #else
            #expect(TabQuickSwitchSettings.listAnimationSettings(in: reopened) == .defaults,
                    "Release rendering ignores debug preferences")
            #endif
            #expect(TabQuickSwitchSettings.spotlightDuration(in: reopened) == 0.65)
        }
    }

    @Test("Animation durations safely handle out-of-range and non-finite values")
    func durationBounds() {
        #expect(TabQuickSwitchSettings.listDurationRange == 0.1...1.5)
        #expect(TabQuickSwitchSettings.listDurationStep == 0.05)
        #expect(TabQuickSwitchSettings.clampedListSwitchDuration(-1) == 0.1)
        #expect(TabQuickSwitchSettings.clampedListSwitchDuration(2) == 1.5)
        #expect(TabQuickSwitchSettings.clampedListSwitchDuration(0.8) == 0.8)
        #expect(TabQuickSwitchSettings.clampedListEntranceDuration(-1) == 0.1)
        #expect(TabQuickSwitchSettings.clampedListEntranceDuration(2) == 1.5)
        #expect(TabQuickSwitchSettings.clampedListEntranceDuration(1.2) == 1.2)
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(TabQuickSwitchSettings.clampedListSwitchDuration(value) == 0.25)
            #expect(TabQuickSwitchSettings.clampedListEntranceDuration(value) == 0.15)
        }
    }

    @Test("Stored invalid styles and duration types fall back without changing other settings")
    func invalidPreferences() throws {
        try withDefaults { defaults, _ in
            defaults.set("unknown", forKey: TabQuickSwitchSettings.listSwitchStyleKey)
            defaults.set("unknown", forKey: TabQuickSwitchSettings.listEntranceStyleKey)
            defaults.set("invalid", forKey: TabQuickSwitchSettings.listSwitchDurationKey)
            defaults.set("invalid", forKey: TabQuickSwitchSettings.listEntranceDurationKey)
            #expect(TabQuickSwitchSettings.listAnimationSettings(in: defaults) == .defaults)

            defaults.set(-8, forKey: TabQuickSwitchSettings.listSwitchDurationKey)
            defaults.set(9, forKey: TabQuickSwitchSettings.listEntranceDurationKey)
            let resolved = TabQuickSwitchSettings.listAnimationSettings(in: defaults)
            #if DEBUG
            #expect(resolved.switchDuration == 0.1)
            #expect(resolved.entranceDuration == 1.5)
            #else
            #expect(resolved == .defaults)
            #endif
            #expect(defaults.double(forKey: TabQuickSwitchSettings.listSwitchDurationKey) == -8,
                    "Reading clamps effective values without rewriting stored preferences")
        }
    }

    @Test("Animation reset changes only the two styles and three animation durations")
    func resetPreservesUserChoices() throws {
        try withDefaults { defaults, _ in
            defaults.set(TabQuickSwitchListSwitchStyle.immediate.rawValue,
                         forKey: TabQuickSwitchSettings.listSwitchStyleKey)
            defaults.set(TabQuickSwitchListEntranceStyle.scale.rawValue,
                         forKey: TabQuickSwitchSettings.listEntranceStyleKey)
            defaults.set(1.1, forKey: TabQuickSwitchSettings.listSwitchDurationKey)
            defaults.set(1.3, forKey: TabQuickSwitchSettings.listEntranceDurationKey)
            defaults.set(0.95, forKey: TabQuickSwitchSettings.spotlightAnimationDurationKey)
            defaults.set(false, forKey: TabQuickSwitchSettings.enabledKey)
            defaults.set(TabQuickSwitchLayout.bubbles.rawValue, forKey: TabQuickSwitchSettings.layoutKey)
            defaults.set(0.8, forKey: TabQuickSwitchSettings.holdDurationKey)
            defaults.set("keep", forKey: "unrelated.preference")

            TabQuickSwitchSettings.resetAnimationSettings(in: defaults)

            #expect(defaults.string(forKey: TabQuickSwitchSettings.listSwitchStyleKey) == "movingCard")
            #expect(defaults.string(forKey: TabQuickSwitchSettings.listEntranceStyleKey) == "fade")
            #expect(defaults.double(forKey: TabQuickSwitchSettings.listSwitchDurationKey) == 0.25)
            #expect(defaults.double(forKey: TabQuickSwitchSettings.listEntranceDurationKey) == 0.15)
            #expect(TabQuickSwitchSettings.spotlightDuration(in: defaults) == 0.45)
            #expect(TabQuickSwitchSettings.listAnimationSettings(in: defaults) == .defaults)
            #expect(!TabQuickSwitchSettings.isEnabled(in: defaults))
            #expect(defaults.string(forKey: TabQuickSwitchSettings.layoutKey) == "bubbles")
            #expect(defaults.double(forKey: TabQuickSwitchSettings.holdDurationKey) == 0.8)
            #expect(defaults.string(forKey: "unrelated.preference") == "keep")
        }
    }

    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let name = "TabQuickSwitchListAnimationSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, name)
    }
}
