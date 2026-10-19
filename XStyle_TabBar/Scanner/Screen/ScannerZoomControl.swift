import SwiftUI

/// Camera-style zoom buttons: the widest zoom and a close-up preset.
/// The button the current zoom falls under shows it, so a pinch reads out
/// here too. Reads the zoom itself, so a pinch redraws only this.
struct ScannerZoomControl: View {
    let model: ScannerModel

    var body: some View {
        if let zoom = model.zoom {
            ScannerZoomOptions(zoom: zoom, factor: model.zoomFactor, onSelect: select)
        }
    }

    /// Eases to `factor`; the model keeps it within the camera's range.
    private func select(_ factor: Double) {
        model.setZoom(factor, animated: true)
    }
}

private struct ScannerZoomOptions: View {
    let zoom: CameraZoom
    let factor: Double
    let onSelect: (Double) -> Void

    var body: some View {
        let presets = zoom.presets
        let activeIndex = zoom.presetIndex(for: factor)

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(presets.indices, id: \.self) { index in
                    let isActive = index == activeIndex

                    Button {
                        onSelect(presets[index])
                    } label: {
                        Text(isActive ? "\(Self.format(factor))×" : Self.format(presets[index]))
                            .font(.footnote.bold().monospacedDigit())
                            .foregroundStyle(isActive ? .yellow : .white)
                            .padding(.horizontal, 8)
                            .frame(minWidth: TopMenuMetrics.minimumTapSize, minHeight: TopMenuMetrics.minimumTapSize)
                            .background(.black.opacity(isActive ? 0.45 : 0.25), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Menu {
                ForEach(presets, id: \.self) { preset in
                    Button("\(Self.format(preset)) times") { onSelect(preset) }
                }
            } label: {
                Text("\(Self.format(factor))×")
                    .font(.footnote.bold().monospacedDigit())
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 12)
                    .frame(minWidth: TopMenuMetrics.minimumTapSize, minHeight: TopMenuMetrics.minimumTapSize)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
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
            case .increment: onSelect(factor.rounded(.down) + 1)
            case .decrement: onSelect(factor.rounded(.up) - 1)
            @unknown default: break
            }
        }
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
