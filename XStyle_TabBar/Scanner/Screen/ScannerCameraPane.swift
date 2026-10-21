import SwiftUI

/// The camera and everything drawn over it, in the preview layer's space,
/// which codes are mapped into: this pane's size. Camera-style chrome: dark
/// over the feed, in any appearance. While aiming, zoom and the flashlight sit
/// at its foot; the hint is under the pane (`ScannerAimingHint`). The feed
/// stays live behind a result and while the sheet slides over the pane, though
/// nothing is scanned past medium; the camera stops with the sheet at full
/// (`ScannerView`).
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
                ScannerViewfinder(isRevealing: model.revealedCode != nil)
            }

            if model.revealedCode != nil {
                ScanRevealLayer(model: model)
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

/// The reveal over the camera. Its own view, as the only one reading the
/// reveal as it follows the code, so the pane around it doesn't redraw each
/// camera frame.
private struct ScanRevealLayer: View {
    let model: ScannerModel

    var body: some View {
        if let reveal = model.reveal {
            ScanRevealView(reveal: reveal)
        }
    }
}
