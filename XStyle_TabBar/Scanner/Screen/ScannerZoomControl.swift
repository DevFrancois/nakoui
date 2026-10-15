import SwiftUI

/// Camera-style zoom buttons: the widest zoom and the one scanning starts at.
/// The button the current zoom falls under shows it, so a pinch reads out
/// here too.
struct ScannerZoomControl: View {
    let zoom: CameraZoom
    let factor: Double
    let select: (Double) -> Void

    var body: some View {
        let presets = zoom.presets
        let activeIndex = zoom.presetIndex(for: factor)

        HStack(spacing: 4) {
            ForEach(presets.indices, id: \.self) { index in
                let isActive = index == activeIndex

                Button {
                    select(presets[index])
                } label: {
                    Text(isActive ? "\(Self.format(factor))×" : Self.format(presets[index]))
                        .font(.footnote.bold().monospacedDigit())
                        .foregroundStyle(isActive ? .yellow : .white)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(isActive ? 0.45 : 0.25), in: .circle)
                        .scaleEffect(isActive ? 1 : 0.8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy, value: activeIndex)
        .sensoryFeedback(.selection, trigger: activeIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(Self.format(factor)) times")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(zoom.clamped(factor.rounded(.down) + 1))
            case .decrement: select(zoom.clamped(factor.rounded(.up) - 1))
            @unknown default: break
            }
        }
    }

    private static func format(_ factor: Double) -> String {
        factor.formatted(.number.precision(.fractionLength(0...1)))
    }
}

#Preview {
    @Previewable @State var factor = 2.6
    let zoom = CameraZoom(range: 1...5, recommended: 2.6)

    ScannerZoomControl(zoom: zoom, factor: factor) { factor = $0 }
        .padding()
        .background(ScannerBackdropPlaceholder())
        .environment(\.colorScheme, .dark)
}
