//
//  SheetSettingsSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Debug settings below the food report: the pane's motion, and whether the camera scans with a result open.
struct SheetSettingsSection: View {
    @Bindable var settings: SheetSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pane Motion")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Viewport", selection: $settings.viewportMode) {
                        ForEach(ViewportMode.allCases, id: \.self) { mode in
                            Text(mode.title)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(settings.viewportMode.caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                /// The pane only moves when it follows the sheet.
                Group {
                    SettingToggle(
                        title: "Stretch",
                        caption: "The pane narrows with the sheet's speed.",
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
                    }
                    .disabled(!settings.paneStretch)
                }
                .disabled(settings.viewportMode != .resizing)

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
                .disabled(!settings.sheetBounce || settings.viewportMode != .resizing)

                if reduceMotion {
                    Text("Reduce Motion is on: no stretch and no bounce.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Scanning")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                SettingToggle(
                    title: "Scan with a result open",
                    caption: "Another barcode replaces the result. Off, the camera scans again once the result is dismissed.",
                    isOn: $settings.scansWithResultOpen
                )

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Found code", selection: $settings.revealStyle) {
                        ForEach(ScanRevealStyle.allCases, id: \.self) { style in
                            Text(style.title)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(settings.revealStyle.caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SettingToggle(
                    title: "Blur behind the found code",
                    caption: "The frozen camera frame blurs as the code lifts off it. Off, it stays sharp.",
                    isOn: $settings.revealBlur
                )
                /// Only the full reveal freezes the camera.
                .disabled(settings.revealStyle != .fullReveal)
            }
        }
        .padding(16)
        .background(SheetCardFill.color, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

private extension ViewportMode {
    var title: LocalizedStringResource {
        switch self {
        case .resizing: "Resizing"
        case .fixed: "Fixed"
        case .receding: "Receding"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .resizing: "The camera shrinks above the sheet down to medium, then recedes as the sheet covers it."
        case .fixed: "The camera keeps its size and place, and the sheet covers it."
        case .receding: "The camera stays in place under the sheet, shrinking a little as it opens and more at full."
        }
    }
}

private extension ScanRevealStyle {
    var title: LocalizedStringResource {
        switch self {
        case .liveBrackets: "Live brackets"
        case .fullReveal: "Full reveal"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .liveBrackets: "The camera stays live: the brackets close on the code and follow it, then let go."
        case .fullReveal: "The camera freezes, and the code lifts off the frame into a card with the product icon."
        }
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
