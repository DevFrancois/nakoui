import SwiftUI

/// The Scan tab: a live camera in the rounded top pane, above the custom
/// bottom sheet. A code that comes into view raises the sheet to medium with
/// its report at once, while the camera shows it (`ScanRevealStyle`): brackets
/// closing on it over the live feed, or Code Scanner's frozen reveal fading
/// back to live. Closing the result sends the sheet below the screen again.
/// Wide windows put the camera and the report side by side.
struct ScannerView: View {
    let model: ScannerModel
    /// Owned above the Scan tab, which is rebuilt with every update of the
    /// tabs, so a pass never constructs throwaway ones.
    let sheet: SheetController
    let settings: SheetSettings
    /// Whether the Scan tab is showing. The camera only runs while it is.
    let isActive: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The latest code found. The sheet keeps showing it while it slides
    /// away after the result closes.
    @State private var shownCode: ScannedCode?
    /// The camera's one preview layer, kept across layout changes, which
    /// rebuild the camera pane.
    @State private var previewHost = CameraPreviewHost()
    @State private var isSideBySide = false
    /// Illustrative until products are looked up.
    private let analysis = PetFoodAnalysis.example

    var body: some View {
        Group {
            if isSideBySide {
                SplitPane(
                    breakpoint: .constant(.half), breakpoints: [.half],
                    sideBySideFraction: ScannerMetrics.sideBySideResultFraction
                ) {
                    ScannerCameraPane(model: model, previewHost: previewHost)
                } bottom: {
                    sideResult
                }
            } else {
                PaneSheetLayout(sheet: sheet, settings: settings) {
                    ScannerCameraPane(model: model, previewHost: previewHost)
                } paneFooter: {
                    ScannerAimingHint(isShown: model.isAiming && model.scannedCode == nil)
                } header: {
                    if let shownCode {
                        header(for: shownCode)
                    }
                } content: {
                    if let shownCode {
                        report(for: shownCode, horizontalPadding: sheet.metrics.scrollContentPadding,
                               bottomPadding: sheet.canvas.safeAreaBottom)
                    }
                }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            ScannerMetrics.usesSideBySide(in: proxy.size)
        } action: { isSideBySide in
            self.isSideBySide = isSideBySide
        }
        // A found code opens the sheet; a closed one sends it away.
        .onChange(of: model.scannedCode?.id, initial: true) {
            if let code = model.scannedCode {
                shownCode = code
                sheet.settle(to: .medium, velocity: 0)
            } else if sheet.detent != .hidden {
                // Already hidden when dragged away: settling again would
                // drop the fling's speed.
                sheet.settle(to: .hidden, velocity: 0)
            }
        }
        // Dragging the sheet below the screen closes the result.
        .onChange(of: sheet.detent) {
            if sheet.detent == .hidden, model.scannedCode != nil {
                model.scanAgain()
            }
        }
        .sensoryFeedback(.success, trigger: model.revealedCode) { _, newCode in
            newCode != nil
        }
        .onChange(of: reduceMotion, initial: true) {
            model.reduceMotion = reduceMotion
        }
        .onChange(of: settings.scansWithResultOpen, initial: true) {
            model.scansWithResultOpen = settings.scansWithResultOpen
        }
        .onChange(of: settings.revealStyle, initial: true) {
            model.revealStyle = settings.revealStyle
        }
        .onChange(of: settings.revealBlur, initial: true) {
            model.revealBlurs = settings.revealBlur
        }
        .onChange(of: displayScale) {
            model.updateDisplayScale(displayScale)
        }
        .modifier(ScannerCameraLifecycle(model: model, sheet: sheet, isActive: isActive, isSideBySide: isSideBySide))
    }

    private func header(for code: ScannedCode) -> some View {
        SheetHeader(
            title: analysis.recipe,
            // Digit by digit, not as one huge number.
            subtitle: Text("\(Text(code.symbology.title)) · \(Text(code.value).speechSpellsOutCharacters())"),
            onClose: model.scanAgain
        )
    }

    private func report(for code: ScannedCode, horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        BottomSheetView(
            analysis: analysis,
            code: code,
            settings: settings,
            horizontalPadding: horizontalPadding,
            bottomPadding: bottomPadding,
            onScanAgain: model.scanAgain
        )
    }

    /// The trailing pane side by side: the sheet's header over its report,
    /// always open, as there is room for both.
    private var sideResult: some View {
        ZStack {
            if let code = model.scannedCode {
                VStack(spacing: 0) {
                    header(for: code)
                        .padding(.horizontal, SheetMetrics.contentPadding)
                        .frame(height: SheetMetrics.current.headerHeight)

                    report(for: code, horizontalPadding: SheetMetrics.contentPadding, bottomPadding: 0)
                }
                .transition(.blurReplace)
            } else {
                ContentUnavailableView(
                    "No Product Scanned", systemImage: "barcode.viewfinder",
                    description: Text("Point the camera at a product barcode.")
                )
                .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: model.scannedCode)
    }
}

/// Runs the camera while the Scan tab shows, and holds it stopped while the
/// result sheet rests at full over it: the camera indicator turns off, and
/// the camera starts again as the sheet leaves full. Its own modifier, so
/// these changes don't re-run the scanner's layout.
private struct ScannerCameraLifecycle: ViewModifier {
    let model: ScannerModel
    let sheet: SheetController
    let isActive: Bool
    /// Side by side, there's no sheet over the camera.
    let isSideBySide: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let isCameraActive = isActive && scenePhase == .active
        content
            .task(id: isCameraActive) {
                guard isCameraActive else { return }
                await model.run()
            }
            .onChange(of: !isSideBySide && sheet.restsAtFull, initial: true) { _, isCovered in
                model.setCameraSuspended(isCovered)
            }
    }
}

// Previews pass `isActive: false`, so the camera never starts and the preset
// state stays put. Simulate Scan plays the whole reveal in live previews.

#if DEBUG
#Preview("Scanning") {
    ScannerView(
        model: ScannerModel(state: .scanning, zoom: CameraZoom(range: 1...5, recommended: 2.6), hasTorch: true),
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(), isActive: false
    )
}

#Preview("Result") {
    ScannerView(
        model: ScannerModel(state: .scanning, scannedCode: .sampleEAN13),
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(), isActive: false
    )
}

#Preview("Camera Denied") {
    ScannerView(
        model: ScannerModel(state: .denied),
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(), isActive: false
    )
}

#Preview("Camera Unavailable") {
    ScannerView(
        model: ScannerModel(state: .unavailable),
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(), isActive: false
    )
}
#endif
