@preconcurrency import AVFoundation
import SwiftUI

/// The live camera feed behind the scanner. SwiftUI has no camera preview of
/// its own, so this hosts AVFoundation's preview layer: the one `host` keeps,
/// moved into a container of this view's own.
struct CameraPreview: UIViewRepresentable {
    let host: CameraPreviewHost
    let device: AVCaptureDevice
    let onRotationChange: (CameraImageRotation) -> Void

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        host.show(in: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // Another container may have taken it since, such as across a layout change.
        host.show(in: container)
        host.view.onRotationChange = onRotationChange
        host.view.device = device
        host.view.setNeedsLayout()
    }
}

/// Keeps one preview layer for as long as the Scan tab. SwiftUI rebuilds the
/// camera pane across layout changes, but a session keeps a single preview
/// layer: giving it a new one removes the old, which reconfigures the running
/// session on the main thread. On a device that deadlocked against
/// AVFoundation's own notifications for about 10 s, then left the new layer
/// black. The layer is attached before camera startup, then the same view
/// moves into each new container without reconfiguring the running session.
final class CameraPreviewHost {
    private(set) lazy var view = CameraPreviewLayerView()

    /// Called before capture starts, while associating the layer cannot
    /// rebuild a running capture graph on the main thread.
    func prepare(session: AVCaptureSession) {
        guard view.previewLayer.session !== session else { return }
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
    }

    func show(in container: UIView) {
        let view = view
        guard view.superview !== container else { return }
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(view)
    }
}
