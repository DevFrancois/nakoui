import SwiftUI

/// Everything drawn over the camera, in the preview layer's space, which
/// codes are mapped into: this pane's size. The live feed itself is
/// `ScannerCameraFeed`, drawn under this pane. Camera-style chrome: dark over
/// the feed, in any appearance. While aiming, the hint, zoom and the
/// flashlight sit at its foot. The feed stays live behind a result.
struct ScannerCameraPane: View {
    let model: ScannerModel
    @Environment(\.displayScale) private var displayScale
    /// While the pane collapses, its feed fades out under it.
    @Environment(\.paneIsCollapsing) private var paneIsCollapsing
    /// The zoom a pinch started from; nil between pinches, including ones
    /// cut short, such as by a code being found.
    @GestureState private var pinchStartZoom: Double?

    var body: some View {
        ZStack {
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    model.updateScreen(size: size, displayScale: displayScale)
                }

            if paneIsCollapsing {
                // The pane only collapses with a result open: the frame its
                // code was found in stands in for the feed.
                Color.black
                if let resultFrame = model.resultFrame {
                    FrozenFrameBackdrop(frozen: resultFrame, blur: 0)
                }
            } else {
                // Previews and the Simulator have no camera feed.
                if model.session == nil {
                    ScannerBackdropPlaceholder()
                }

                if (model.state == .idle || model.state == .scanning) && !model.isPausedForResult {
                    ScannerViewfinder(isRevealing: model.reveal != nil)
                }

                if let reveal = model.reveal {
                    ScanRevealView(reveal: reveal)
                }

                if model.state == .denied || model.state == .unavailable {
                    ScannerUnavailableView(state: model.state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(ScannerMetrics.scrimOpacity))
                }
            }
        }
        .contentShape(.rect)
        .gesture(pinch, isEnabled: canZoom)
        .overlay(alignment: .bottom) {
            // Removed, not just faded, before the pane collapses: its glass
            // can't be flattened either.
            ZStack {
                if isAiming {
                    aimingControls
                        .transition(.opacity)
                }
            }
            // The pane drops its transactions' animations; this one is its own.
            .animation(.easeOut(duration: 0.15), value: isAiming)
        }
        .environment(\.colorScheme, .dark)
        // Nothing is scanned while the camera is out of view.
        .onChange(of: paneIsCollapsing, initial: true) {
            model.setCameraHidden(paneIsCollapsing)
        }
    }

    private var aimingControls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                // Not over a result: the pane is short above its sheet, and
                // scanning on is already the camera's doing.
                if model.scannedCode == nil {
                    Label("Point at a product barcode", systemImage: "barcode.viewfinder")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                }

                #if targetEnvironment(simulator)
                ScannerSimulateButton(action: model.simulateScan)
                #endif

                if model.zoom != nil || model.hasTorch {
                    HStack(spacing: 12) {
                        ScannerZoomControl(model: model)
                        if model.hasTorch {
                            ScannerTorchButton(model: model)
                        }
                    }
                }
            }
        }
        .padding(.bottom)
    }

    /// The camera controls show while aiming, not while a found code is
    /// revealed, a result is waited on, or the pane collapses.
    private var isAiming: Bool {
        model.isAiming && !paneIsCollapsing
    }

    private var canZoom: Bool {
        isAiming && model.zoom != nil
    }

    /// Scales the zoom from where the pinch started, like the Camera app.
    private var pinch: some Gesture {
        MagnifyGesture()
            .updating($pinchStartZoom) { value, start, _ in
                let base = start ?? model.liveZoomFactor
                start = base
                model.setZoom(base * value.magnification, animated: false)
            }
    }
}
