import SwiftUI

/// The camera and everything drawn over it, in the preview layer's space,
/// which codes are mapped into: this pane's size. Camera-style chrome: dark
/// over the feed, in any appearance. While aiming, the hint, zoom and the
/// flashlight sit at its foot. The feed stays live behind a result, and while
/// the sheet slides over the pane.
struct ScannerCameraPane: View {
    let model: ScannerModel
    /// Owned above this pane, which a layout change rebuilds, so the feed
    /// keeps its one preview layer.
    let previewHost: CameraPreviewHost
    @Environment(\.displayScale) private var displayScale
    /// Whether the sheet is over the pane, on its way to full.
    @Environment(\.paneIsCovered) private var paneIsCovered
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

            if let session = model.session, let device = model.cameraDevice {
                CameraPreview(host: previewHost, session: session, device: device,
                              onRotationChange: model.updatePreviewRotation)
            } else {
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
        .background(.black)
        .contentShape(.rect)
        .gesture(pinch, isEnabled: canZoom)
        .overlay(alignment: .bottom) {
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
        // Nothing is scanned while the sheet slides over the camera.
        .onChange(of: paneIsCovered, initial: true) {
            model.setCameraHidden(paneIsCovered)
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
    /// revealed, a result is waited on, or the sheet covers the pane.
    private var isAiming: Bool {
        model.isAiming && !paneIsCovered
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
