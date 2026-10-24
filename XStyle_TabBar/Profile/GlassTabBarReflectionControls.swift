import SwiftUI

struct GlassTabBarReflectionControls: View {
    @Binding var configuration: GlassTabBarReflectionConfiguration
    @State private var isRimExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reflection")
                .font(.headline)

            Toggle("Enable reflection", isOn: $configuration.isEnabled)
                .accessibilityIdentifier("reflection.isEnabled")

            ReflectionValueSlider(title: "Saturation", value: $configuration.saturation,
                                  range: GlassTabBarReflectionConfiguration.Ranges.saturation,
                                  identifier: "reflection.saturation")
            ReflectionValueSlider(title: "Brightness", value: $configuration.brightness,
                                  range: GlassTabBarReflectionConfiguration.Ranges.brightness,
                                  identifier: "reflection.brightness")
            ReflectionValueSlider(title: "Blur", value: $configuration.blurRadius,
                                  range: GlassTabBarReflectionConfiguration.Ranges.blurRadius, step: 0.25,
                                  identifier: "reflection.blurRadius")
            ReflectionValueSlider(title: "Opacity", value: $configuration.opacity,
                                  range: GlassTabBarReflectionConfiguration.Ranges.opacity,
                                  identifier: "reflection.opacity")

            Toggle("Mirror reflection", isOn: $configuration.isMirrored)
                .accessibilityIdentifier("reflection.isMirrored")

            DisclosureGroup(isExpanded: $isRimExpanded) {
                ReflectionRimControls(configuration: $configuration)
                    .padding(.top, 12)
            } label: {
                Text("Rim and geometry")
                    .accessibilityIdentifier("reflection.rimSettings")
            }

            Button("Reset to reference", systemImage: "arrow.counterclockwise") {
                configuration = .reference
            }
            .buttonStyle(.bordered)
            .disabled(configuration == .reference)
            .accessibilityIdentifier("reflection.reset")
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

private struct ReflectionRimControls: View {
    @Binding var configuration: GlassTabBarReflectionConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReflectionValueSlider(title: "Rim softness", value: $configuration.rimRadius,
                                  range: GlassTabBarReflectionConfiguration.Ranges.rimRadius, step: 0.25,
                                  identifier: "reflection.rimRadius")
            ReflectionValueSlider(title: "Rim opacity", value: $configuration.rimOpacity,
                                  range: GlassTabBarReflectionConfiguration.Ranges.opacity,
                                  identifier: "reflection.rimOpacity")
            ReflectionValueSlider(title: "Horizontal offset", value: $configuration.rimOffsetX,
                                  range: GlassTabBarReflectionConfiguration.Ranges.rimOffset, step: 0.25,
                                  identifier: "reflection.rimOffsetX")
            ReflectionValueSlider(title: "Vertical offset", value: $configuration.rimOffsetY,
                                  range: GlassTabBarReflectionConfiguration.Ranges.rimOffset, step: 0.25,
                                  identifier: "reflection.rimOffsetY")
            ReflectionValueSlider(title: "Rim expansion", value: $configuration.rimExpansion,
                                  range: GlassTabBarReflectionConfiguration.Ranges.rimExpansion, step: 0.25,
                                  identifier: "reflection.rimExpansion")
            ReflectionValueSlider(title: "Edge coverage", value: $configuration.edgeCoverage,
                                  range: GlassTabBarReflectionConfiguration.Ranges.edgeCoverage,
                                  identifier: "reflection.edgeCoverage")
        }
    }
}

private struct ReflectionValueSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .accessibilityValue(Text(value, format: .number.precision(.fractionLength(2))))
            .accessibilityIdentifier(identifier)
        }
    }
}
