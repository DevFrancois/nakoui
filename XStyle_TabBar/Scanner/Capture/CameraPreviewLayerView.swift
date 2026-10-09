@preconcurrency import AVFoundation
import UIKit

/// Shows the camera feed, upright and aspect-filled: the geometry
/// `AspectFillMapper` assumes when it places codes on screen.
final class CameraPreviewLayerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("layerClass makes the backing layer an AVCaptureVideoPreviewLayer.")
        }
        return previewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Portrait-only: the back camera's landscape frames turn 90°. Set it
        // explicitly, since codes are placed on screen assuming it.
        if let connection = previewLayer.connection, connection.videoRotationAngle != 90,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
