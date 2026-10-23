@preconcurrency import AVFoundation
import OSLog
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
    /// Hidden until the feed shows frames, over the pane's black. The view
    /// fades, not a layer over it: AVFoundation draws the video in sublayers
    /// of its own, which can sit above any of ours.
    private var isCovered = true

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
        let isCovered = PreviewCover.isCovered(
            isPreviewing: previewLayer.isPreviewing,
            isInWindow: window != nil,
            wasCovered: self.isCovered
        )
        #if DEBUG
        Self.logger.debug("Preview: previewing \(self.previewLayer.isPreviewing), window \(self.window != nil), covered \(isCovered)")
        #endif
        guard isCovered != self.isCovered else { return }
        self.isCovered = isCovered
        layer.removeAnimation(forKey: "opacity")
        guard !isCovered else {
            UIView.performWithoutAnimation { alpha = 0 }
            return
        }
        // The sensor's first resumed frames can briefly change brightness or
        // color. Ease in the feed itself while the scanner chrome stays steady.
        // Its own timing, even when a move into a window runs inside another
        // animation, such as a tab transition.
        UIView.animate(withDuration: 0.18, delay: 0,
                       options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction,
                                 .overrideInheritedDuration, .overrideInheritedCurve]) {
            self.alpha = 1
        }
    }

    #if DEBUG
    private static let logger = Logger(subsystem: "dev.kavsoft.XStyle-TabBar", category: "scanner")
    #endif

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

/// When the preview is hidden over the pane's black.
nonisolated enum PreviewCover {
    static func isCovered(
        isPreviewing: Bool, isInWindow: Bool, wasCovered: Bool
    ) -> Bool {
        // Whenever frames stop, the feed hides: under the result sheet at
        // full, on leaving the tab, or when the system interrupts the camera.
        // It comes back from black, never a frozen frame.
        guard isPreviewing else { return true }
        // Reparenting an already-live preview during layout keeps it visible.
        // A fresh run waits for both a window and actual preview frames.
        return wasCovered && !isInWindow
    }
}
