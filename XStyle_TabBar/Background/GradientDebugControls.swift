#if DEBUG
import SwiftUI

/// Sliders for the Home background's intensity and depth, shared by Profile
/// settings and the side menu. Compiled into debug builds only.
struct GradientDebugControls: View {
    @AppStorage(AmbientGradientTuning.intensityKey) private var intensity = AmbientGradientTuning.defaultIntensity
    @AppStorage(AmbientGradientTuning.depthKey) private var depth = AmbientGradientTuning.defaultDepth

    private var isDefault: Bool {
        intensity == AmbientGradientTuning.defaultIntensity && depth == AmbientGradientTuning.defaultDepth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            DebugPanelHeader(title: "Background", systemImage: "circle.lefthalf.filled", isDefault: isDefault, reset: reset)

            DebugSliderRow(title: "Intensity", value: $intensity, range: AmbientGradientTuning.intensityRange)
            DebugSliderRow(title: "Depth", value: $depth, range: AmbientGradientTuning.depthRange)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 4)
    }

    private func reset() {
        intensity = AmbientGradientTuning.defaultIntensity
        depth = AmbientGradientTuning.defaultDepth
    }
}

#Preview {
    GradientDebugControls()
}
#endif
