#if DEBUG
import SwiftUI

/// The For you cards' glass material and strength, at the bottom of the side
/// menu. Compiled into debug builds only, so it never ships.
struct FeedGlassDebugControls: View {
    @AppStorage(FeedGlassTuning.materialKey) private var material = FeedGlassTuning.defaultMaterial
    @AppStorage(FeedGlassTuning.strengthKey) private var strength = FeedGlassTuning.defaultStrength
    @AppStorage(FeedGlassTuning.whiteFillKey) private var whiteFill = FeedGlassTuning.defaultWhiteFill

    private var isDefault: Bool {
        material == FeedGlassTuning.defaultMaterial && strength == FeedGlassTuning.defaultStrength
            && whiteFill == FeedGlassTuning.defaultWhiteFill
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            DebugPanelHeader(title: "Card glass", systemImage: "square.on.square", isDefault: isDefault, reset: reset)

            Picker("Material", selection: $material) {
                ForEach(FeedGlassTuning.Material.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            // The white fill is opaque and hides the glass behind it.
            .disabled(whiteFill)

            DebugSliderRow(title: "Strength", value: $strength, range: 0...1)
                .disabled(material == .off || whiteFill)

            Toggle("White cards", isOn: $whiteFill)
                .font(.caption.bold())
                .controlSize(.mini)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 4)
    }

    private func reset() {
        material = FeedGlassTuning.defaultMaterial
        strength = FeedGlassTuning.defaultStrength
        whiteFill = FeedGlassTuning.defaultWhiteFill
    }
}

#Preview {
    FeedGlassDebugControls()
}
#endif
