@preconcurrency import AVFoundation
import OSLog
import SwiftUI

/// The live camera feed behind the scanner. SwiftUI has no camera preview of
/// its own, so this hosts AVFoundation's preview layer: the one `host` keeps,
/// moved into a container of this view's own.
struct CameraPreview: UIViewRepresentable {
    let host: CameraPreviewHost
    let session: AVCaptureSession
    let device: AVCaptureDevice
    let onRotationChange: (CameraImageRotation) -> Void

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        host.show(in: container, session: session)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // Another container may have taken it since, such as across a layout change.
        host.show(in: container, session: session)
        host.view.onRotationChange = onRotationChange
        host.view.device = device
        host.view.setNeedsLayout()
    }
}

/// Keeps one preview layer for as long as the Scan tab. SwiftUI rebuilds the
/// feed's view, such as across layout changes, but a session keeps a single
/// preview layer: giving it a new one removes the old, which reconfigures the
/// running session on the main thread. On a device that deadlocked against
/// AVFoundation's own notifications for about 10 s, then left the new layer
/// black. So the same view moves into each new container, and the session is
/// set on its layer once.
final class CameraPreviewHost {
    private(set) lazy var view = CameraPreviewLayerView()

    func show(in container: UIView, session: AVCaptureSession) {
        let view = view
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
        }
        guard view.superview !== container else { return }
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(view)
        #if DEBUG
        logState("shown")
        #endif
    }

    #if DEBUG
    /// One line on whether frames reach the layer, for device runs.
    func logState(_ event: String) {
        let layer = view.previewLayer
        let session = layer.session?.isRunning == true ? "running" : "stopped"
        let connection = layer.connection.map { $0.isEnabled && $0.isActive ? "live" : "idle" } ?? "none"
        let previewing = layer.isPreviewing ? "previewing" : "not previewing"
        let screen = view.window == nil ? "off screen" : "on screen"
        Self.logger.debug("Preview: \(event), session \(session), connection \(connection), \(previewing), \(screen)")
    }

    private static let logger = Logger(subsystem: "dev.kavsoft.XStyle-TabBar", category: "scanner")
    #endif
}
