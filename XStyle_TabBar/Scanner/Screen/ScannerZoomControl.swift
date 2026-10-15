import SwiftUI

/// Camera-style zoom buttons: the widest zoom and the one scanning starts at.
/// The button the current zoom falls under shows it, so a pinch reads out
/// here too. Reads the zoom itself, so a pinch redraws only this.
struct ScannerZoomControl: View {
    let model: ScannerModel

    var body: some View {
        if let zoom = model.zoom {
            buttons(zoom: zoom, factor: model.zoomFactor)
        }
    }

    private func buttons(zoom: CameraZoom, factor: Double) -> some View {
        let presets = zoom.presets
        let activeIndex = zoom.presetIndex(for: factor)

        return HStack(spacing: 4) {
            ForEach(presets.indices, id: \.self) { index in
                let isActive = index == activeIndex

                Button {
                    select(presets[index])
                } label: {
                    Text(isActive ? "\(Self.format(factor))×" : Self.format(presets[index]))
                        .font(.footnote.bold().monospacedDigit())
                        .foregroundStyle(isActive ? .yellow : .white)
                        .frame(width: ScannerMetrics.zoomButtonSize, height: ScannerMetrics.zoomButtonSize)
                        .background(.black.opacity(isActive ? 0.45 : 0.25), in: .circle)
                        .scaleEffect(isActive ? 1 : 0.8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(ScannerMetrics.zoomButtonInset)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy, value: activeIndex)
        .sensoryFeedback(.selection, trigger: activeIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(Self.format(factor)) times")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(factor.rounded(.down) + 1)
            case .decrement: select(factor.rounded(.up) - 1)
            @unknown default: break
            }
        }
    }

    /// Eases to `factor`; the model keeps it within the camera's range.
    private func select(_ factor: Double) {
        model.setZoom(factor, animated: true)
    }

    private static func format(_ factor: Double) -> String {
        factor.formatted(.number.precision(.fractionLength(0...1)))
    }
}

#Preview {
    ScannerZoomControl(model: ScannerModel(state: .scanning, zoom: CameraZoom(range: 1...5, recommended: 2.6)))
        .padding()
        .background(ScannerBackdropPlaceholder())
        .environment(\.colorScheme, .dark)
}
