#if DEBUG
import SwiftUI

/// The editor lives in the Profile destination; the actual tab bar is the
/// preview. Its nearby color/photo strip stays fixed while the controls scroll.
struct ProfileReflectionSettings: View {
    @Environment(\.tabBarReflectionTuning) private var tuning

    var body: some View {
        if let tuning {
            if #available(iOS 27.1, *) {
                AdaptiveProfileReflectionEditor(tuning: tuning)
            } else {
                ProfileReflectionEditor(tuning: tuning, previewEdge: nil)
            }
        } else {
            ContentUnavailableView("Reflection controls unavailable", systemImage: "slider.horizontal.3")
        }
    }
}

@available(iOS 27.1, *)
private struct AdaptiveProfileReflectionEditor: View {
    let tuning: TabBarReflectionTuningStore
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        ProfileReflectionEditor(tuning: tuning, previewEdge: verticalEdge)
    }
}

private struct ProfileReflectionEditor: View {
    let tuning: TabBarReflectionTuningStore
    let previewEdge: HorizontalEdge?

    var body: some View {
        let layout = previewEdge != nil
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        layout {
            if previewEdge == .leading {
                PinnedReflectionPreview(isVertical: true)
            }
            ProfileReflectionControls(tuning: tuning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A ScrollView may draw into the top safe area when the
                // navigation bar is hidden. Clip its allocated viewport so
                // scrolled controls cannot overlap the system status items.
                .clipped()
            if previewEdge != .leading {
                PinnedReflectionPreview(isVertical: previewEdge != nil)
            }
        }
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
        .onDisappear { tuning.flush() }
    }
}

private struct PinnedReflectionPreview: View {
    let isVertical: Bool

    var body: some View {
        ProfileReflectionPreview(isVertical: isVertical)
            // Keep a generous band of source colors outside the capsule's
            // feedback exclusion, including above the horizontal floating bar.
            .frame(width: isVertical ? 100 : nil, height: isVertical ? nil : 180)
            .frame(maxHeight: isVertical ? .infinity : nil)
    }
}

private struct ProfileReflectionControls: View {
    let tuning: TabBarReflectionTuningStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isShowingOtherSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile").font(.largeTitle.bold())
                    Text("Tab bar reflections").font(.title2.bold())
                    Text("Adjust the menu in real time. Your values are saved on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if reduceTransparency {
                    Label("Reduce Transparency is on. The menu stays opaque and sampled reflections are hidden.",
                          systemImage: "accessibility")
                        .font(.footnote)
                }
                ProfileReflectionMode(tuning: tuning)
                ReflectionControlSection(title: "Surface", tuning: tuning,
                    parameters: [.surfaceOpacity, .faceWash])
                ReflectionControlSection(title: "Reflected colors", tuning: tuning,
                    parameters: [.reflectionStrength, .reflectionWidth, .saturation, .softness, .samplingDistance])
                ReflectionControlSection(title: "Edge lighting", tuning: tuning,
                    parameters: [.sharpHighlight, .sharpHighlightWidth, .softGlow, .softGlowWidth,
                                 .lightDirectionDegrees, .warmCoolBalance, .edgeDarkening])
                Button("Reset defaults", systemImage: "arrow.counterclockwise") {
                    tuning.resetDefaults()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reflection.resetDefaults")
                Button("Other debug settings", systemImage: "slider.horizontal.3") {
                    isShowingOtherSettings = true
                }
                .accessibilityIdentifier("profile.debugSettings")
            }
            .padding(16)
        }
        .accessibilityIdentifier("reflection.controls")
        .sheet(isPresented: $isShowingOtherSettings) { ProfileDebugSettings() }
    }
}

private struct ProfileReflectionMode: View {
    @Bindable var tuning: TabBarReflectionTuningStore

    var body: some View {
        Picker("Reflection mode", selection: $tuning.mode) {
            Text("Face and edges").tag(TabBarReflectionSettings.Mode.faceAndEdges)
            Text("Mostly edges").tag(TabBarReflectionSettings.Mode.mostlyEdges)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("reflection.mode")
        .onChange(of: tuning.mode) { tuning.flush() }
    }
}

private struct ReflectionControlSection: View {
    let title: LocalizedStringResource
    let tuning: TabBarReflectionTuningStore
    let parameters: [TabBarReflectionSettings.Parameter]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            ForEach(parameters, id: \.self) { parameter in
                ReflectionSliderRow(tuning: tuning, parameter: parameter)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ReflectionSliderRow: View {
    @Bindable var tuning: TabBarReflectionTuningStore
    let parameter: TabBarReflectionSettings.Parameter
    @Environment(\.locale) private var locale

    var body: some View {
        let value = $tuning[dynamicMember: parameter.storeKeyPath]
        let displayedValue = parameter.formatted(value.wrappedValue, locale: locale)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(parameter.title).font(.subheadline)
                Spacer(minLength: 8)
                Text(displayedValue)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Slider(value: value, in: parameter.range) { isEditing in
                if !isEditing { tuning.flush() }
            }
            .accessibilityLabel(Text(parameter.title))
            .accessibilityValue(displayedValue)
            .accessibilityIdentifier("reflection.\(parameter.rawValue)")
        }
        .disabled(parameter == .faceWash && tuning.mode == .mostlyEdges)
    }
}

private struct ProfileReflectionPreview: View {
    let isVertical: Bool
    @State private var showsPhotos = false
    @State private var sampleIndex = 0
    private let images: [ImageResource] = [.pic1, .pic2, .pic3]
    private let colors: [Color] = [.blue, .pink, .green]

    var body: some View {
        VStack(spacing: 6) {
            let buttons = isVertical
                ? AnyLayout(VStackLayout(spacing: 6))
                : AnyLayout(HStackLayout(spacing: 16))
            buttons {
                Button { showsPhotos.toggle() } label: {
                    if isVertical {
                        Image(systemName: showsPhotos ? "photo" : "paintpalette")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    } else {
                        Text(showsPhotos ? "Photos" : "Colors")
                    }
                }
                    .accessibilityLabel("Preview source")
                    .accessibilityValue(showsPhotos ? "Photos" : "Colors")
                    .accessibilityHint("Switch between color swatches and article photos")
                    .accessibilityIdentifier("reflection.previewSource")
                Button {
                    sampleIndex = (sampleIndex + 1) % images.count
                } label: {
                    if isVertical {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    } else {
                        Label("Next", systemImage: "arrow.right")
                    }
                }
                .accessibilityLabel("Next preview sample")
                .accessibilityIdentifier("reflection.previewNext")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            if showsPhotos {
                ArticleThumbnailImage(image: images[sampleIndex])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let swatches = isVertical
                    ? AnyLayout(VStackLayout(spacing: 0))
                    : AnyLayout(HStackLayout(spacing: 0))
                swatches {
                    ForEach(0..<colors.count, id: \.self) { index in
                        colors[(index + sampleIndex) % colors.count]
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .accessibilityLabel("Blue, pink, and green preview swatches")
            }
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

private extension TabBarReflectionSettings.Parameter {
    var title: LocalizedStringResource {
        switch self {
        case .surfaceOpacity: "Surface opacity"
        case .faceWash: "Face color wash"
        case .reflectionStrength: "Reflection strength"
        case .reflectionWidth: "Reflection width"
        case .saturation: "Color saturation"
        case .softness: "Reflection softness"
        case .samplingDistance: "Sampling distance"
        case .sharpHighlight: "Sharp highlight strength"
        case .sharpHighlightWidth: "Sharp highlight width"
        case .softGlow: "Soft glow strength"
        case .softGlowWidth: "Soft glow width"
        case .lightDirectionDegrees: "Lighting direction"
        case .warmCoolBalance: "Warm/cool balance"
        case .edgeDarkening: "Edge darkening"
        }
    }

    var storeKeyPath: ReferenceWritableKeyPath<TabBarReflectionTuningStore, Double> {
        switch self {
        case .surfaceOpacity: \.surfaceOpacity
        case .faceWash: \.faceWash
        case .reflectionStrength: \.reflectionStrength
        case .reflectionWidth: \.reflectionWidth
        case .saturation: \.saturation
        case .softness: \.softness
        case .samplingDistance: \.samplingDistance
        case .sharpHighlight: \.sharpHighlight
        case .sharpHighlightWidth: \.sharpHighlightWidth
        case .softGlow: \.softGlow
        case .softGlowWidth: \.softGlowWidth
        case .lightDirectionDegrees: \.lightDirectionDegrees
        case .warmCoolBalance: \.warmCoolBalance
        case .edgeDarkening: \.edgeDarkening
        }
    }

    func formatted(_ value: Double, locale: Locale) -> String {
        switch self {
        case .surfaceOpacity, .faceWash:
            value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
        case .reflectionWidth, .samplingDistance, .sharpHighlightWidth, .softGlowWidth:
            value.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + " pt"
        case .lightDirectionDegrees:
            value.formatted(.number.precision(.fractionLength(0)).locale(locale)) + "°"
        case .warmCoolBalance:
            value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        default:
            value.formatted(.number.precision(.fractionLength(2)).locale(locale)) + "×"
        }
    }
}

#Preview {
    ProfileReflectionSettings()
        .environment(\.tabBarReflectionTuning, TabBarReflectionTuningStore())
}
#endif
