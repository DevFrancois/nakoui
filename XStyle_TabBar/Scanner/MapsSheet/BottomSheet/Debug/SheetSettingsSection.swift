//
//  SheetSettingsSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Debug settings below the food report.
struct SheetSettingsSection: View {
    @Bindable var settings: SheetSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                /// The picker carries the same label for VoiceOver.
                Text("Pane Effect")
                    .font(.headline)
                    .accessibilityHidden(true)

                Picker("Pane Effect", selection: $settings.paneEffect) {
                    ForEach(PaneEffect.allCases) { effect in
                        Text(effect.title)
                            .tag(effect)
                    }
                }
                .pickerStyle(.segmented)

                Text(reduceMotion ? "Reduce Motion is on: every pane effect uses a simple fade." : settings.paneEffect.caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Pane Motion")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                SettingToggle(
                    title: "Stretch",
                    caption: "The pane deforms with the sheet's speed.",
                    isOn: $settings.paneStretch
                )

                /// Each depends on the stretch.
                Group {
                    SettingToggle(
                        title: "Smooth the stretch",
                        caption: "No overshoot, a filtered speed, and still touch moves ignored.",
                        isOn: $settings.smoothStretch
                    )

                    SettingToggle(
                        title: "Horizontal squash",
                        caption: "Narrows the pane by up to \(PaneTuning.maxSquash, format: .percent.precision(.fractionLength(0...1))).",
                        isOn: $settings.paneSquash
                    )

                    SettingToggle(
                        title: "Collapse deformation",
                        caption: "Bends the collapse into the Dynamic Island: width, corners and funnel pinch.",
                        isOn: $settings.paneDeformation
                    )
                }
                .disabled(!settings.paneStretch)

                SettingToggle(
                    title: "Sheet bounce",
                    caption: "The sheet overshoots its detent when it settles.",
                    isOn: $settings.sheetBounce
                )

                SettingToggle(
                    title: "Pane follows the bounce",
                    caption: "Off, the pane waits at the detent while the sheet overshoots it.",
                    isOn: $settings.paneFollowsBounce
                )
                .disabled(!settings.sheetBounce)

                if reduceMotion {
                    Text("Reduce Motion is on: no stretch and no bounce.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(SheetCardFill.color, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// A toggle with a one-line explanation under its title.
private struct SettingToggle: View {
    let title: LocalizedStringResource
    let caption: LocalizedStringResource
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)

                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview("Debug settings", traits: .fixedLayout(width: 393, height: 650)) {
    @Previewable @State var settings = PreviewFixtures.makeSettings()

    ScrollView {
        SheetSettingsSection(settings: settings)
            .padding(SheetMetrics.current.scrollContentPadding)
    }
    .background(Color(.systemBackground))
}

#Preview("Large Text · Dark", traits: .fixedLayout(width: 393, height: 650)) {
    @Previewable @State var settings = PreviewFixtures.makeSettings()

    ScrollView {
        SheetSettingsSection(settings: settings)
            .padding(SheetMetrics.current.scrollContentPadding)
    }
    .background(Color(.systemBackground))
    .dynamicTypeSize(.xxLarge)
    .preferredColorScheme(.dark)
}
#endif
