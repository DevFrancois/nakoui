import SwiftUI

/// The search scope, which the Search tab's quick switch menu changes, and
/// how the quick switch menus look. Search itself isn't built yet.
struct SearchTabPage: View {
    @AppStorage(SearchScope.storageKey) private var scope = SearchScope.defaultScope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label {
                    Text(RootTab.search.title)
                } icon: {
                    Image(systemName: RootTab.search.symbol)
                }
                .font(.title2.bold())

                Picker("Search in", selection: $scope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("search.scope")

                ContentUnavailableView {
                    Label {
                        Text(scope.title)
                    } icon: {
                        Image(systemName: scope.symbol)
                    }
                } description: {
                    Text(scope.placeholderDescription)
                }

                QuickSwitchAppearanceSection()
            }
            .padding()
        }
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
    }
}

/// How the quick switch menus draw the eye and lay out their items. The
/// menus themselves are turned on and off on the Profile page.
private struct QuickSwitchAppearanceSection: View {
    @AppStorage(TabQuickSwitchSettings.enabledKey) private var isEnabled = TabQuickSwitchSettings.defaultEnabled
    @AppStorage(TabQuickSwitchSettings.layoutKey) private var layout = TabQuickSwitchLayout.defaultLayout
    @AppStorage(TabQuickSwitchSettings.holdDurationKey)
    private var holdDuration = TabQuickSwitchSettings.defaultHoldDuration
    #if DEBUG
    @State private var isShowingQuickSwitchDebug = false
    #endif

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Layout")
                        .font(.subheadline.weight(.semibold))
                    Picker("Layout", selection: $layout) {
                        ForEach(TabQuickSwitchLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("search.quickSwitch.layout")
                    Text(layout.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent {
                        Text(holdDurationText)
                            .monospacedDigit()
                    } label: {
                        Text("Hold time")
                            .font(.subheadline.weight(.semibold))
                    }
                    Slider(value: $holdDuration, in: TabQuickSwitchSettings.holdDurationRange,
                           step: TabQuickSwitchSettings.holdDurationStep) {
                        Text("Hold time")
                    } minimumValueLabel: {
                        Text(seconds(TabQuickSwitchSettings.holdDurationRange.lowerBound))
                    } maximumValueLabel: {
                        Text(seconds(TabQuickSwitchSettings.holdDurationRange.upperBound))
                    }
                    .accessibilityValue(holdDurationText)
                    .accessibilityIdentifier("search.quickSwitch.holdDuration")
                    Text("How long to hold a tab to begin. Then slide between tabs and menus without lifting your finger.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Button("Quick Switch Debug", systemImage: "slider.horizontal.3") {
                    isShowingQuickSwitchDebug = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("search.quickSwitch.debug")
                #endif
            }
            .disabled(!isEnabled)

            if !isEnabled {
                Text("Quick switch is off. Turn it on in Profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        } label: {
            Text("Quick switch")
        }
        #if DEBUG
        .sheet(isPresented: $isShowingQuickSwitchDebug) {
            QuickSwitchDebugSettings()
        }
        #endif
    }

    private var holdDurationText: String {
        seconds(TabQuickSwitchSettings.clampedHoldDuration(holdDuration))
    }

    private func seconds(_ value: Double) -> String {
        Duration.seconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated,
                                                 fractionalPart: .show(length: 2)))
    }
}

#if DEBUG
private struct QuickSwitchDebugSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TabQuickSwitchSettings.listSwitchStyleKey)
    private var switchStyle = TabQuickSwitchListAnimationSettings.defaults.switchStyle
    @AppStorage(TabQuickSwitchSettings.listEntranceStyleKey)
    private var entranceStyle = TabQuickSwitchListAnimationSettings.defaults.entranceStyle
    @AppStorage(TabQuickSwitchSettings.listSwitchDurationKey)
    private var switchDuration = TabQuickSwitchListAnimationSettings.defaults.switchDuration
    @AppStorage(TabQuickSwitchSettings.listEntranceDurationKey)
    private var entranceDuration = TabQuickSwitchListAnimationSettings.defaults.entranceDuration
    @AppStorage(TabQuickSwitchSettings.spotlightAnimationDurationKey)
    private var spotlightDuration = TabQuickSwitchSettings.defaultSpotlightDuration

    var body: some View {
        NavigationStack {
            Form {
                QuickSwitchListSwitchSection(style: $switchStyle, duration: $switchDuration)
                QuickSwitchListEntranceSection(style: $entranceStyle, duration: $entranceDuration)
                QuickSwitchSpotlightSection(duration: $spotlightDuration)
                Section {
                    Button("Reset animation defaults") {
                        TabQuickSwitchSettings.resetAnimationSettings()
                    }
                    .disabled(usesDefaultAnimations)
                    .accessibilityIdentifier("search.quickSwitch.resetAnimations")
                }
            }
            .navigationTitle("Quick Switch Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private var usesDefaultAnimations: Bool {
        let defaults = TabQuickSwitchListAnimationSettings.defaults
        return switchStyle == defaults.switchStyle && entranceStyle == defaults.entranceStyle
            && switchDuration == defaults.switchDuration && entranceDuration == defaults.entranceDuration
            && spotlightDuration == TabQuickSwitchSettings.defaultSpotlightDuration
    }
}

private struct QuickSwitchListSwitchSection: View {
    @Binding var style: TabQuickSwitchListSwitchStyle
    @Binding var duration: Double

    var body: some View {
        Section {
            Picker("Switch style", selection: $style) {
                ForEach(TabQuickSwitchListSwitchStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("search.quickSwitch.listSwitchStyle")
            QuickSwitchAnimationDurationControls(
                title: "Switch duration", storedDuration: $duration,
                defaultDuration: TabQuickSwitchListAnimationSettings.defaults.switchDuration,
                range: TabQuickSwitchSettings.listDurationRange, step: TabQuickSwitchSettings.listDurationStep,
                accessibilityID: "search.quickSwitch.listSwitchDuration"
            )
            .disabled(style == .immediate)
        } header: {
            Text("List switching")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(style.summary)
                Text("These controls apply only to List. Bubbles keep their current animation.")
            }
        }
    }
}

private struct QuickSwitchListEntranceSection: View {
    @Binding var style: TabQuickSwitchListEntranceStyle
    @Binding var duration: Double

    var body: some View {
        Section {
            Picker("Entrance style", selection: $style) {
                ForEach(TabQuickSwitchListEntranceStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("search.quickSwitch.listEntranceStyle")
            QuickSwitchAnimationDurationControls(
                title: "Entrance duration", storedDuration: $duration,
                defaultDuration: TabQuickSwitchListAnimationSettings.defaults.entranceDuration,
                range: TabQuickSwitchSettings.listDurationRange, step: TabQuickSwitchSettings.listDurationStep,
                accessibilityID: "search.quickSwitch.listEntranceDuration"
            )
        } header: {
            Text("List entrance")
        } footer: {
            Text(style.summary)
        }
    }
}

private struct QuickSwitchSpotlightSection: View {
    @Binding var duration: Double

    var body: some View {
        Section {
            QuickSwitchAnimationDurationControls(
                title: "Movement duration", storedDuration: $duration,
                defaultDuration: TabQuickSwitchSettings.defaultSpotlightDuration,
                range: TabQuickSwitchSettings.spotlightDurationRange,
                step: TabQuickSwitchSettings.spotlightDurationStep,
                accessibilityID: "search.quickSwitch.spotlightDuration"
            )
        } header: {
            Text("Spotlight")
        } footer: {
            Text("Controls how long the spotlight takes to move and resize around the active area. New targets are tracked immediately. Reduce Motion keeps movement and resizing instant.")
        }
    }
}

private struct QuickSwitchAnimationDurationControls: View {
    let title: LocalizedStringResource
    @Binding var storedDuration: Double
    let defaultDuration: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityID: String

    var body: some View {
        Group {
            LabeledContent {
                Text(seconds(storedDuration[clampedTo: range, fallback: defaultDuration]))
                    .monospacedDigit()
            } label: {
                Text(title)
            }
            Slider(value: $storedDuration[clampedTo: range, fallback: defaultDuration], in: range, step: step) {
                Text(title)
            } minimumValueLabel: {
                Text(seconds(range.lowerBound))
            } maximumValueLabel: {
                Text(seconds(range.upperBound))
            }
            .accessibilityValue(seconds(storedDuration[clampedTo: range, fallback: defaultDuration]))
            .accessibilityIdentifier(accessibilityID)
        }
    }

    private func seconds(_ value: Double) -> String {
        Duration.seconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated,
                                                 fractionalPart: .show(length: 2)))
    }
}

/// A key-path projection keeps invalid stored values out of the sliders.
private extension Double {
    subscript(clampedTo range: ClosedRange<Double>, fallback fallback: Double) -> Double {
        get { isFinite ? min(max(self, range.lowerBound), range.upperBound) : fallback }
        set { self = newValue.isFinite ? min(max(newValue, range.lowerBound), range.upperBound) : fallback }
    }
}
#endif

#Preview {
    SearchTabPage()
}
