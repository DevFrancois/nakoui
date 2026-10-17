import SwiftUI

/// The aiming frame: a clear window with corner brackets and dimming around
/// it. The window comes from `ScannerMetrics.viewfinderRect(in:)`,
/// the same rect the camera scans. While a code is revealed the reveal draws
/// the brackets, and the dimming fades away.
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
