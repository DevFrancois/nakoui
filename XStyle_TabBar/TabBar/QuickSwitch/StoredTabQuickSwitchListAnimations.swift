import SwiftUI

/// Observes debug tuning without allowing persisted experiments to affect
/// release builds. Both the renderer and bar cancellation use this snapshot.
@propertyWrapper
struct StoredTabQuickSwitchListAnimations: DynamicProperty {
    #if DEBUG
    @AppStorage(TabQuickSwitchSettings.listSwitchStyleKey)
    private var switchStyle = TabQuickSwitchListSwitchStyle.movingCard
    @AppStorage(TabQuickSwitchSettings.listEntranceStyleKey)
    private var entranceStyle = TabQuickSwitchListEntranceStyle.fade
    @AppStorage(TabQuickSwitchSettings.listSwitchDurationKey)
    private var switchDuration = TabQuickSwitchListAnimationSettings.defaults.switchDuration
    @AppStorage(TabQuickSwitchSettings.listEntranceDurationKey)
    private var entranceDuration = TabQuickSwitchListAnimationSettings.defaults.entranceDuration
    #endif

    var wrappedValue: TabQuickSwitchListAnimationSettings {
        #if DEBUG
        TabQuickSwitchListAnimationSettings(
            switchStyle: switchStyle, entranceStyle: entranceStyle,
            switchDuration: TabQuickSwitchSettings.clampedListSwitchDuration(switchDuration),
            entranceDuration: TabQuickSwitchSettings.clampedListEntranceDuration(entranceDuration)
        )
        #else
        .defaults
        #endif
    }
}
