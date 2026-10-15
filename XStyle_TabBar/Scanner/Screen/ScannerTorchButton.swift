import SwiftUI

/// Lights the code in the dark: the camera's torch, sized to sit beside the
/// zoom buttons.
struct ScannerTorchButton: View {
    let model: ScannerModel

    var body: some View {
        Button(action: model.toggleTorch) {
            Image(systemName: model.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(model.isTorchOn ? .yellow : .white)
                .frame(width: ScannerMetrics.cameraControlSize, height: ScannerMetrics.cameraControlSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isTorchOn)
        .accessibilityLabel("Flashlight")
        .accessibilityValue(model.isTorchOn ? "On" : "Off")
    }
}

#Preview {
    ScannerTorchButton(model: ScannerModel(state: .scanning, hasTorch: true))
        .padding()
        .background(ScannerBackdropPlaceholder())
        .environment(\.colorScheme, .dark)
}
