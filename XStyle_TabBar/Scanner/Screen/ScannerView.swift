import SwiftUI

/// The Scan tab: a live camera with a viewfinder. A code that comes into view
/// is revealed with Code Scanner's animation, then shown in a Liquid Glass sheet.
struct ScannerView: View {
    @Bindable var model: ScannerModel
    /// Whether the Scan tab is showing. The camera only runs while it is.
    let isActive: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Full screen, in the preview layer's space, which codes are mapped
            // into. Camera-style chrome: dark over the feed, in any appearance.
            ZStack {
                Color.clear
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { size in
                        model.updateScreen(size: size, displayScale: displayScale)
                    }

                if let session = model.session {
                    CameraPreview(session: session)
                } else {
                    ScannerBackdropPlaceholder()
                }

                if model.state == .idle || model.state == .scanning {
                    ScannerViewfinder(isRevealing: model.reveal != nil)
                }
            }
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)

            if model.state == .denied || model.state == .unavailable {
                // Inside the safe area: readable text and a button.
                ScannerUnavailableView(state: model.state)
                    .background {
                        Color.black.opacity(ScannerMetrics.scrimOpacity)
                            .ignoresSafeArea()
                    }
                    .environment(\.colorScheme, .dark)
            }

            if let reveal = model.reveal {
                ScanRevealView(reveal: reveal)
            }
        }
        #if targetEnvironment(simulator)
        .safeAreaBar(edge: .bottom) {
            ScannerSimulateButton(action: model.simulateScan)
                .disabled(model.reveal != nil)
                .environment(\.colorScheme, .dark)
        }
        #endif
        .sheet(item: $model.scannedCode, onDismiss: model.resultDidClose, content: ScannedCodeSheet.init)
        .sensoryFeedback(.success, trigger: model.reveal?.code) { _, newCode in
            newCode != nil
        }
        .onChange(of: reduceMotion, initial: true) {
            model.reduceMotion = reduceMotion
        }
        .task(id: isActive) {
            guard isActive else { return }
            await model.run()
        }
    }
}

// Previews pass `isActive: false`, so the camera never starts and the preset
// state stays put. Simulate Scan plays the whole reveal in live previews.

#Preview("Scanning") {
    ScannerView(model: ScannerModel(state: .scanning), isActive: false)
}

#Preview("Result") {
    ScannerView(model: ScannerModel(state: .scanning, scannedCode: .sampleEAN13), isActive: false)
}

#Preview("Camera Denied") {
    ScannerView(model: ScannerModel(state: .denied), isActive: false)
}

#Preview("Camera Unavailable") {
    ScannerView(model: ScannerModel(state: .unavailable), isActive: false)
}
