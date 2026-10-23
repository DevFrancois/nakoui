@preconcurrency import AVFoundation
import UIKit

/// Coordinates the actual capture device with this scene's preview layer.
/// The analyzer receives the same rotation that the connection displays.
final class CameraPreviewLayerView: UIView {
    var device: AVCaptureDevice? {
        didSet {
            if device !== oldValue { updateRotationCoordinator() }
        }
    }
    var onRotationChange: ((CameraImageRotation) -> Void)?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var reportedRotation: CameraImageRotation?
    private var previewObservation: NSKeyValueObservation?
    private var isShowingPreview = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        alpha = 0
        previewObservation = previewLayer.observe(\.isPreviewing, options: [.initial, .new]) { [weak self] _, _ in
            // This KVO callback has no main-queue guarantee. Read the current
            // readiness after the hop so queued notifications cannot show an
            // already-stopped session.
            Task { @MainActor [weak self] in
                self?.updatePreviewVisibility()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

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
        applyRotation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRotationCoordinator()
        updatePreviewVisibility()
    }

    private func updatePreviewVisibility() {
        guard previewLayer.isPreviewing else {
            isShowingPreview = false
            layer.removeAnimation(forKey: "opacity")
            UIView.performWithoutAnimation { alpha = 0 }
            return
        }
        // Reparenting an already-live preview during layout keeps it visible.
        // A fresh run waits for both a window and actual preview frames.
        guard window != nil, !isShowingPreview else { return }
        isShowingPreview = true
        // The sensor's first resumed frames can briefly change brightness or
        // color. Ease in the feed itself while the scanner chrome stays steady.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 1
        }
    }

    private func updateRotationCoordinator() {
        rotationObservation = nil
        rotationCoordinator = nil
        reportedRotation = nil
        // A coordinator reports zero until its layer is in a view hierarchy.
        guard window != nil, let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
            // AVFoundation documents main-queue delivery. Apply synchronously
            // so the preview connection participates in the system rotation.
            MainActor.assumeIsolated { self?.applyRotation() }
        }
    }

    private func applyRotation() {
        guard window != nil, let rotationCoordinator, let connection = previewLayer.connection else { return }
        let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        guard angle.isFinite, connection.isVideoRotationAngleSupported(angle) else { return }
        if connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
        let rotation = CameraImageRotation(degrees: angle)
        guard reportedRotation != rotation else { return }
        reportedRotation = rotation
        // Scalar state crosses back after UIKit's layout callback; only the
        // connection update above must be synchronous with system rotation.
        Task { @MainActor [weak self] in
            guard let self, reportedRotation == rotation else { return }
            onRotationChange?(rotation)
        }
    }
}
