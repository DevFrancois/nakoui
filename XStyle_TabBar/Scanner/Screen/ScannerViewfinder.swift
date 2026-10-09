import SwiftUI

/// The aiming frame: the camera dimmed around a clear window, corner brackets,
/// and a hint below. The window comes from `ScannerMetrics.viewfinderRect(in:)`,
/// the same rect the camera scans. While a code is revealed the reveal draws
/// the brackets, and the dimming and hint fade away.
struct ScannerViewfinder: View {
    var isRevealing = false

    var body: some View {
        ZStack {
            ViewfinderCutout()
                .fill(.black.opacity(ScannerMetrics.scrimOpacity), style: FillStyle(eoFill: true))
                .opacity(isRevealing ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: isRevealing)

            ViewfinderBrackets()
                .stroke(.white, style: StrokeStyle(lineWidth: ScannerMetrics.bracketLineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(ScannerMetrics.bracketShadowOpacity), radius: 1.5)
                .opacity(isRevealing ? 0 : 1)
                .animation(isRevealing ? nil : .easeOut(duration: 0.3), value: isRevealing)
                .accessibilityHidden(true)

            // Full screen, like the shapes, so the hint can sit under the window.
            GeometryReader { proxy in
                let window = ScannerMetrics.viewfinderRect(in: CGRect(origin: .zero, size: proxy.size))

                Label("Point at a product barcode", systemImage: "barcode.viewfinder")
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .glassEffect(in: .capsule)
                    .frame(maxWidth: .infinity)
                    .padding(.top, window.maxY + ScannerMetrics.hintSpacing)
                    .opacity(isRevealing ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: isRevealing)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ScannerViewfinder()
        .background {
            ScannerBackdropPlaceholder()
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
}
