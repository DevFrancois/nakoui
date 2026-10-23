import SwiftUI

/// The Scan tab: a live camera in the rounded top pane, above the custom
/// bottom sheet. A code that comes into view raises the sheet to medium with
/// its report at once, while the camera shows it (`ScanRevealStyle`): brackets
/// closing on it over the live feed, or Code Scanner's frozen reveal fading
/// back to live. Closing the result sends the sheet below the screen again.
/// Every scan goes into the history, which a button in the camera's top-leading
/// corner opens in the same sheet, at full, once the first result has closed. Wide windows put the
/// camera and the report side by side.
struct ScannerView: View {
    let model: ScannerModel
    /// Owned above the Scan tab, which is rebuilt with every update of the
    /// tabs, so a pass never constructs throwaway ones.
    let sheet: SheetController
    let settings: SheetSettings
    let history: ScanHistory
    /// Whether the Scan tab is showing. The camera only runs while it is.
    let isActive: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the sheet shows: a result, the history, or a product from it. It
    /// keeps showing it while it slides away.
    @State private var sheetState = ScanSheetState()
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
                    sideBySideFraction: ScannerMetrics.sideBySideResultFraction,
                    topEffect: ScannerViewportAppearance(entrance: model.viewportEntrance, isActive: isActive)
                ) {
                    // The pane's top-leading corner is the screen's: inset
                    // clear of the island.
                    cameraPane(historyButtonInset: 16)
                } bottom: {
                    sideResult
                }
            } else {
                PaneSheetLayout(sheet: sheet, settings: settings,
                                paneEffect: ScannerViewportAppearance(entrance: model.viewportEntrance, isActive: isActive)) {
                    // Concentric with the viewport's rounded corner.
                    cameraPane(historyButtonInset: PaneMetrics.viewportCornerRadius - TopMenuMetrics.minimumTapSize / 2)
                } paneFooter: {
                    // The hint until the first result closes; then the
                    // camera eases into its room. In a stack, which reports
                    // no height once it's empty.
                    ZStack {
                        if !history.isButtonRevealed {
                            ScannerAimingHint(isShown: model.isAiming && model.scannedCode == nil && !history.hasScanned)
                        }
                    }
                } header: {
                    sheetHeader(for: sheetState.route)
                } content: {
                    sheetContent(for: sheetState.route, horizontalPadding: sheet.metrics.scrollContentPadding,
                                 bottomPadding: sheet.canvas.safeAreaBottom)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            ScannerMetrics.usesSideBySide(in: proxy.size)
        } action: { isSideBySide in
            self.isSideBySide = isSideBySide
        }
        // A found code opens the sheet; a closed one sends it away. The model
        // keeps the history of both.
        .onChange(of: model.scannedCode?.id, initial: true) {
            if let code = model.scannedCode {
                apply(sheetState.found(code))
            } else {
                apply(sheetState.resultClosed())
            }
        }
        // Dragging the sheet below the screen closes the result.
        .onChange(of: sheet.detent) {
            if sheet.detent != .hidden {
                model.viewportEntrance.finish()
            }
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
        .modifier(ScannerCameraLifecycle(model: model, previewHost: previewHost, sheet: sheet,
                                         isActive: isActive, isSideBySide: isSideBySide))
    }

    /// The camera, with the history button over its top-leading corner once
    /// the first result has closed. Its tip waits for the sheet to go.
    private func cameraPane(historyButtonInset: CGFloat) -> some View {
        ScannerCameraPane(model: model, previewHost: previewHost)
            .overlay(alignment: .topLeading) {
                ZStack {
                    if history.isButtonRevealed {
                        ScanHistoryButton(
                            history: history, showsTip: sheet.detent == .hidden, cornerInset: historyButtonInset,
                            action: openHistory
                        )
                        .transition(.opacity)
                    }
                }
                // The pane drops its transactions' animations; this one is
                // its own.
                .animation(.easeOut(duration: 0.2), value: history.isButtonRevealed)
                // Camera chrome, like the controls at its foot.
                .environment(\.colorScheme, .dark)
            }
    }

    @ViewBuilder
    private func sheetHeader(for route: ScanSheetRoute?) -> some View {
        switch route {
        case .result(let code):
            productHeader(for: code, onBack: nil, onClose: model.scanAgain)
        case .history:
            SheetHeader(
                title: Text("Scan History"),
                subtitle: Text("^[\(history.entries.count) product](inflect: true)"),
                onClose: closeSheet
            ) {
                ScanHistoryClearButton(history: history)
            }
        case .entry(let code):
            productHeader(for: code, onBack: { apply(sheetState.back()) }, onClose: closeSheet)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sheetContent(for route: ScanSheetRoute?, horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        switch route {
        case .result(let code):
            report(for: code, horizontalPadding: horizontalPadding, bottomPadding: bottomPadding, onScanAgain: model.scanAgain)
        case .history:
            ScanHistoryList(history: history, horizontalPadding: horizontalPadding, bottomPadding: bottomPadding) { entry in
                apply(sheetState.show(entry.makeCode()))
            }
        case .entry(let code):
            // Scanning again means going back to the camera.
            report(for: code, horizontalPadding: horizontalPadding, bottomPadding: bottomPadding, onScanAgain: closeSheet)
        case nil:
            EmptyView()
        }
    }

    private func productHeader(for code: ScannedCode, onBack: (() -> Void)?, onClose: @escaping () -> Void) -> some View {
        SheetHeader(
            title: analysis.recipe,
            // Digit by digit, not as one huge number.
            subtitle: Text("\(Text(code.symbology.title)) · \(Text(code.value).speechSpellsOutCharacters())"),
            onBack: onBack,
            onClose: onClose
        )
    }

    private func report(
        for code: ScannedCode, horizontalPadding: CGFloat, bottomPadding: CGFloat, onScanAgain: @escaping () -> Void
    ) -> some View {
        BottomSheetView(
            analysis: analysis,
            code: code,
            settings: settings,
            history: history,
            horizontalPadding: horizontalPadding,
            bottomPadding: bottomPadding,
            onScanAgain: onScanAgain
        )
    }

    private func openHistory() {
        apply(sheetState.showHistory())
    }

    private func closeSheet() {
        apply(sheetState.close())
    }

    /// Carries out a route change, after the route itself has changed: the
    /// sheet takes the new route's detents, and closing a result for the
    /// history then leaves the sheet up.
    private func apply(_ effects: [ScanSheetEffect]) {
        if let detents = sheetState.route?.detents, sheet.presentationDetents != detents {
            sheet.presentationDetents = detents
        }
        for effect in effects {
            switch effect {
            case .present(let detent):
                // Never down: a result found over the history keeps its place.
                if sheet.detent < detent {
                    sheet.settle(to: detent, velocity: 0)
                }
            case .hide:
                // Already hidden when dragged away: settling again would drop
                // the fling's speed.
                if sheet.detent != .hidden {
                    sheet.settle(to: .hidden, velocity: 0)
                }
            case .closeResult:
                model.scanAgain()
            }
        }
    }

    /// What the sheet shows while it's up; side by side, the trailing pane
    /// shows it with room to spare.
    private var presentedRoute: ScanSheetRoute? {
        sheet.detent == .hidden ? nil : sheetState.route
    }

    /// The trailing pane side by side: the sheet's header over its content,
    /// always open, as there is room for both.
    private var sideResult: some View {
        ZStack {
            if let route = presentedRoute {
                VStack(spacing: 0) {
                    sheetHeader(for: route)
                        .padding(.horizontal, SheetMetrics.contentPadding)
                        .frame(height: SheetMetrics.current.headerHeight)

                    sheetContent(for: route, horizontalPadding: SheetMetrics.contentPadding, bottomPadding: 0)
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
        .animation(.smooth, value: presentedRoute)
    }
}

/// Runs the camera while the Scan tab shows, and holds it stopped while the
/// result sheet rests at full over it: the camera indicator turns off, and
/// the camera starts again as the sheet leaves full. Its own modifier, so
/// these changes don't re-run the scanner's layout.
private struct ScannerCameraLifecycle: ViewModifier {
    let model: ScannerModel
    let previewHost: CameraPreviewHost
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
                await model.run(preparePreview: previewHost.prepare)
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
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(),
        history: PreviewFixtures.makeHistory(), isActive: false
    )
}

#Preview("Result") {
    ScannerView(
        model: ScannerModel(state: .scanning, scannedCode: .sampleEAN13),
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(),
        history: PreviewFixtures.makeHistory(), isActive: false
    )
}

#Preview("Camera Denied") {
    ScannerView(
        model: ScannerModel(state: .denied),
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(),
        history: PreviewFixtures.makeHistory(), isActive: false
    )
}

#Preview("Camera Unavailable") {
    ScannerView(
        model: ScannerModel(state: .unavailable),
        sheet: SheetController(initialDetent: .hidden), settings: PreviewFixtures.makeSettings(),
        history: PreviewFixtures.makeHistory(), isActive: false
    )
}
#endif
