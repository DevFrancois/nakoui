import SwiftUI

/// The Scan tab, split like SplitPaneKit: a live camera with a viewfinder in
/// the top pane, and a pane under it with the aiming hint. A code that comes
/// into view is revealed with Code Scanner's animation, then the pane opens
/// with its details. Wide windows put the panes side by side.
struct ScannerView: View {
    let model: ScannerModel
    /// Whether the Scan tab is showing. The camera only runs while it is.
    let isActive: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paneBreakpoint = SplitPaneBreakpoint.peek
    @State private var isSideBySide = false

    private static let breakpoints: [SplitPaneBreakpoint] = [.peek, .half, .large]

    var body: some View {
        SplitPane(
            breakpoint: $paneBreakpoint, breakpoints: Self.breakpoints,
            sideBySideFraction: isSideBySide ? ScannerMetrics.sideBySideResultFraction : nil
        ) {
            ScannerCameraPane(model: model)
        } bottom: {
            ScannerResultPane(model: model)
        }
        .onGeometryChange(for: Bool.self) { proxy in
            ScannerMetrics.usesSideBySide(in: proxy.size)
        } action: { isSideBySide in
            self.isSideBySide = isSideBySide
        }
        // A found code opens the pane; a cleared one lets it back down.
        .onChange(of: model.scannedCode?.id, initial: true) {
            paneBreakpoint = model.scannedCode == nil ? .peek : .half
        }
        // Dragging the open pane back down closes the result, as dismissing
        // the sheet did.
        .onChange(of: paneBreakpoint) {
            if paneBreakpoint == .peek, model.scannedCode != nil {
                model.scanAgain()
            }
        }
        .sensoryFeedback(.success, trigger: model.reveal?.code) { _, newCode in
            newCode != nil
        }
        .onChange(of: reduceMotion, initial: true) {
            model.reduceMotion = reduceMotion
        }
        .onChange(of: displayScale) {
            model.updateDisplayScale(displayScale)
        }
        .task(id: isCameraActive) {
            guard isCameraActive else { return }
            await model.run()
        }
    }

    private var isCameraActive: Bool {
        isActive && scenePhase == .active
    }
}

// Previews pass `isActive: false`, so the camera never starts and the preset
// state stays put. Simulate Scan plays the whole reveal in live previews.

#Preview("Scanning") {
    ScannerView(model: ScannerModel(state: .scanning, zoom: CameraZoom(range: 1...5, recommended: 2.6), hasTorch: true), isActive: false)
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
