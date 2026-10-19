import SwiftUI

/// The camera and everything drawn over it, in the preview layer's space,
/// which codes are mapped into: this pane's size. Camera-style chrome: dark
/// over the feed, in any appearance. Zoom and the flashlight sit at its foot.
struct ScannerCameraPane: View {
    let model: ScannerModel
    @Environment(\.displayScale) private var displayScale
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
                CameraPreview(session: session, device: device, onRotationChange: model.updatePreviewRotation)
            } else {
                ScannerBackdropPlaceholder()
            }

            if model.state == .idle || model.state == .scanning {
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
            if model.state == .scanning, model.zoom != nil || model.hasTorch {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        ScannerZoomControl(model: model)
                        if model.hasTorch {
                            ScannerTorchButton(model: model)
                        }
                    }
                }
                .padding(.bottom)
                .opacity(isAiming ? 1 : 0)
                .disabled(!isAiming)
                .animation(.easeOut(duration: 0.15), value: isAiming)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// The camera controls show while aiming, not while a found code is
    /// revealed or shown.
    private var isAiming: Bool {
        model.state == .scanning && model.reveal == nil && model.scannedCode == nil
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
