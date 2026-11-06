import CoreGraphics
import Observation

nonisolated enum ScannerUploadPage: Equatable {
    case camera
    case upload

    var progress: CGFloat { self == .camera ? 0 : 1 }
}

/// Recognition stops as soon as a drag begins; capture stops only once the camera is out of view.
nonisolated struct ScannerUploadCameraActivity: Equatable {
    var blocksRecognition: Bool
    var suspendsCapture: Bool

    static let camera = Self(blocksRecognition: false, suspendsCapture: false)
}

/// The two pages keep their size and share one position, including interrupted springs.
@MainActor @Observable
final class ScannerUploadController {
    private(set) var page = ScannerUploadPage.camera
    private(set) var progress: CGFloat = 0
    private(set) var isDragging = false
    private(set) var isAnimating = false
    private(set) var travelDistance: CGFloat = 1
    var selectedPhotos: Set<Int> = []

    @ObservationIgnored var reduceMotion = false
    /// Synchronous, so a queued camera event cannot beat the next SwiftUI update.
    @ObservationIgnored var onActivityChange: ((ScannerUploadCameraActivity) -> Void)?
    @ObservationIgnored private(set) var dragProgress: CGFloat = 0
    @ObservationIgnored private var dragStartProgress: CGFloat = 0
    @ObservationIgnored private var dragStartPage = ScannerUploadPage.camera
    @ObservationIgnored private var reportedActivity = ScannerUploadCameraActivity.camera
    @ObservationIgnored private let animator: SpringAnimator<CGFloat>

    init(animator: SpringAnimator<CGFloat>? = nil) {
        let animator = animator ?? SpringAnimator<CGFloat>(
            spring: WaveSpring(dampingRatio: 1, response: 0.38), value: 0, target: 0
        )
        self.animator = animator
        animator.valueChanged = { [weak self] value in
            guard let self else { return }
            progress = min(max(value, 0), 1)
            if value == page.progress {
                finish()
            } else {
                publishActivity()
            }
        }
    }

    var activity: ScannerUploadCameraActivity {
        ScannerUploadCameraActivity(
            blocksRecognition: page == .upload || progress > 0 || isDragging || isAnimating,
            suspendsCapture: page == .upload && progress == 1
        )
    }

    var isCameraSettled: Bool { page == .camera && !isDragging && !isAnimating }
    var isUploadSettled: Bool { page == .upload && !isDragging && !isAnimating }

    /// Retain normalized progress through resizing; an in-flight touch cannot keep its old coordinates.
    func updateTravelDistance(_ distance: CGFloat) {
        guard distance > 0, distance != travelDistance else { return }
        travelDistance = distance
        if isDragging {
            page = dragStartPage
            finish()
        }
    }

    func showUpload() { settle(to: .upload, velocity: 0) }
    func showCamera() { settle(to: .camera, velocity: 0) }

    func beginDrag() {
        guard !isDragging else { return }
        animator.stop()
        isAnimating = false
        dragStartPage = page
        dragStartProgress = progress
        dragProgress = progress
        isDragging = true
        publishActivity()
    }

    /// Positive delta is a downward finger move, exposing the camera above Upload.
    func drag(by delta: CGFloat) {
        guard isDragging else { return }
        dragProgress = min(max(dragProgress - delta / travelDistance, 0), 1)
        if !reduceMotion { progress = dragProgress }
        publishActivity()
    }

    func endDrag(velocity: CGFloat, cancelled: Bool) {
        guard isDragging else { return }
        let destination = cancelled ? dragStartPage : Self.destination(
            from: dragStartPage,
            distance: (dragStartProgress - dragProgress) * travelDistance,
            velocity: velocity
        )
        isDragging = false
        settle(to: destination, velocity: cancelled || reduceMotion ? 0 : velocity)
    }

    func cancelDrag() { endDrag(velocity: 0, cancelled: true) }

    /// Leaving the tab clears this demo's ephemeral selection; quick-switch navigation preserves it.
    func reset(clearingSelection: Bool = true) {
        page = .camera
        finish()
        if clearingSelection { selectedPhotos.removeAll() }
    }

    func takeRequest(_: ScanSheetRequest.Route) {
        // Reselecting Scan also returns to its camera, matching the existing history behavior.
        reset(clearingSelection: false)
    }

    /// Also used when the scene backgrounds: never leave two half-visible pages on restoration.
    func finish() {
        animator.stop()
        animator.value = page.progress
        animator.target = page.progress
        animator.velocity = 0
        progress = page.progress
        dragProgress = progress
        isDragging = false
        isAnimating = false
        publishActivity()
    }

    private func settle(to destination: ScannerUploadPage, velocity: CGFloat) {
        page = destination
        isDragging = false
        guard progress != destination.progress else {
            finish()
            return
        }
        isAnimating = true
        publishActivity()
        animator.spring = WaveSpring(dampingRatio: 1, response: reduceMotion ? 0.15 : 0.38)
        animator.target = destination.progress
        animator.restart(value: progress, velocity: min(max(-velocity / travelDistance, -5), 5))
    }

    private func publishActivity() {
        let current = activity
        guard current != reportedActivity else { return }
        reportedActivity = current
        onActivityChange?(current)
    }

    static func destination(from page: ScannerUploadPage, distance: CGFloat, velocity: CGFloat) -> ScannerUploadPage {
        // A deliberate reversal at release wins; otherwise use the net distance, not incidental drift.
        if abs(velocity) > SplitPaneDrag.velocityThreshold { return velocity < 0 ? .upload : .camera }
        if abs(distance) > SplitPaneDrag.distanceThreshold { return distance < 0 ? .upload : .camera }
        return page
    }

    static func canOpen(sheetIsHidden: Bool, sheetHasSettled: Bool, hasResult: Bool, isRevealing: Bool) -> Bool {
        sheetIsHidden && sheetHasSettled && !hasResult && !isRevealing
    }
}
