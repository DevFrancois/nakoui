@preconcurrency import AVFoundation
import SwiftUI

/// The live camera feed behind the scanner. SwiftUI has no camera preview of
/// its own, so this hosts AVFoundation's preview layer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice
    let onRotationChange: (CameraImageRotation) -> Void

    func makeUIView(context: Context) -> CameraPreviewLayerView {
        let view = CameraPreviewLayerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onRotationChange = onRotationChange
        view.device = device
        return view
    }

    func updateUIView(_ view: CameraPreviewLayerView, context: Context) {
        view.onRotationChange = onRotationChange
        view.device = device
        view.setNeedsLayout()
    }
}
