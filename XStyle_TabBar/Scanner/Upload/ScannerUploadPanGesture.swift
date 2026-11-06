import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A vertical page pan that shares the upload grid's scroll gesture. Its
/// global hit region is measured by SwiftUI because the recognizer's UIView
/// can be larger than the surface to which the gesture is attached.
struct ScannerUploadPanGesture: UIGestureRecognizerRepresentable {
    let controller: ScannerUploadController
    let source: ScannerUploadPage
    var isEnabled: Bool
    var hitRegion: CGRect

    func makeCoordinator(converter: CoordinateSpaceConverter) -> ScannerUploadPanCoordinator {
        ScannerUploadPanCoordinator(controller: controller, source: source, isEnabled: isEnabled, hitRegion: hitRegion)
    }

    func makeUIGestureRecognizer(context: Context) -> ScannerUploadPanRecognizer {
        let recognizer = ScannerUploadPanRecognizer()
        context.coordinator.configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: ScannerUploadPanRecognizer, context: Context) {
        context.coordinator.update(controller: controller, source: source, isEnabled: isEnabled, hitRegion: hitRegion)
    }

    func handleUIGestureRecognizerAction(_ recognizer: ScannerUploadPanRecognizer, context: Context) {
        context.coordinator.panDidChange(recognizer)
    }
}

final class ScannerUploadPanRecognizer: UIPanGestureRecognizer {
    var onReset: (() -> Void)?

    func cancelForAdditionalTouch() {
        switch state {
        case .possible: state = .failed
        case .began, .changed: state = .cancelled
        default: break
        }
    }

    override func reset() {
        super.reset()
        onReset?()
    }
}

/// The page consumes upward movement until Upload is fully open. Once it is
/// open, content scrolls normally; a downward pull reaches the content's top
/// before moving the page. Positions are tracked in window coordinates so
/// moving the page never adds movement to the finger's own translation.
final class ScannerUploadPanCoordinator: NSObject, UIGestureRecognizerDelegate {
    private enum Owner { case page, content }

    private var controller: ScannerUploadController
    private var source: ScannerUploadPage
    private var isEnabled: Bool
    private var hitRegion: CGRect
    private weak var recognizer: ScannerUploadPanRecognizer?
    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var frozenOffsetY: CGFloat?
    private var isWritingOffset = false
    private var isDragging = false
    private var hasTouch = false
    private var touchInScrollView = false
    private var owner = Owner.page
    private var lastFingerY: CGFloat = 0
    private var lastOffsetY: CGFloat = 0
    private var lastWrittenOffsetY: CGFloat?
    private var pageMovedInLastMove = false
    private var lastMoveViaScrollTarget = false

    init(controller: ScannerUploadController, source: ScannerUploadPage, isEnabled: Bool, hitRegion: CGRect) {
        self.controller = controller
        self.source = source
        self.isEnabled = isEnabled
        self.hitRegion = hitRegion
    }

    isolated deinit {
        if isDragging, controller.isDragging { controller.cancelDrag() }
        offsetObservation?.invalidate()
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(scrollPanDidChange(_:)))
    }

    func configure(_ recognizer: ScannerUploadPanRecognizer) {
        self.recognizer = recognizer
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        recognizer.isEnabled = isEnabled
        recognizer.onReset = { [weak self] in self?.reset() }
    }

    func update(controller: ScannerUploadController, source: ScannerUploadPage, isEnabled: Bool, hitRegion: CGRect) {
        if self.controller !== controller || self.source != source || !isEnabled {
            cancel()
            detach()
        }
        self.controller = controller
        self.source = source
        self.isEnabled = isEnabled
        self.hitRegion = hitRegion
        recognizer?.isEnabled = isEnabled
        // A rotation or external route change can cancel the controller's
        // drag while UIKit still owns this touch. Never restart it mid-touch.
        if isDragging, !controller.isDragging {
            cancel()
        }
    }

    private var uploadIsOpen: Bool { controller.dragProgress >= 1 }
    private var shouldFreezeContent: Bool { (isDragging && owner == .page) || !uploadIsOpen }
    private var scrollPanIsTracking: Bool {
        guard touchInScrollView, let pan = scrollView?.panGestureRecognizer else { return false }
        return (pan.state == .began || pan.state == .changed) && pan.numberOfTouches == 1
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if hasTouch {
            // Rejecting a second touch alone leaves the recognizer tracking
            // its first finger. Cancel explicitly so a pinch cannot also pan.
            (gestureRecognizer as? ScannerUploadPanRecognizer)?.cancelForAdditionalTouch()
            return false
        }
        guard isEnabled, !isDragging, !controller.isDragging,
              gestureRecognizer.numberOfTouches == 0, let window = touch.window else { return false }
        let point = touch.location(in: nil)
        let visibleRegion = hitRegion.intersection(window.convert(window.bounds, to: nil))
        guard visibleRegion.contains(point),
              source == .camera ? controller.progress < 1 : controller.progress > 0 else { return false }
        if let view = gestureRecognizer.view {
            guard !view.isHidden, view.alpha > 0.01,
                  view.bounds.contains(touch.location(in: view)) else { return false }
        }
        detach()
        if source == .upload,
           let candidate = Self.verticalScrollView(containing: touch.view, below: gestureRecognizer.view) {
            attach(to: candidate)
            touchInScrollView = true
        }
        hasTouch = true
        lastFingerY = point.y
        lastOffsetY = scrollView?.contentOffset.y ?? 0
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer,
              pan.numberOfTouches == 1 else { return false }
        let velocity = pan.velocity(in: nil)
        return abs(velocity.y) > abs(velocity.x) && (source == .upload || velocity.y < 0)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The page pan cancels as soon as a second finger joins. Let the
        // camera's pinch recognize independently of that cancellation.
        if source == .camera, other is UIPinchGestureRecognizer { return true }
        guard source == .upload, touchInScrollView, let scrollView,
              other === scrollView.panGestureRecognizer else { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        // A slider or other nested control owns its drag; the vertical grid
        // instead recognizes simultaneously and shares each movement below.
        other is UIPanGestureRecognizer && !(other.view is UIScrollView)
    }

    func panDidChange(_ pan: ScannerUploadPanRecognizer) {
        switch pan.state {
        case .began:
            guard isEnabled, !controller.isDragging else { return }
            isDragging = true
            owner = uploadIsOpen && touchInScrollView ? .content : .page
            controller.beginDrag()
            process(fingerY: pan.location(in: nil).y, viaScrollTarget: false)
        case .changed:
            guard !scrollPanIsTracking else { return }
            process(fingerY: pan.location(in: nil).y, viaScrollTarget: false)
        case .ended:
            process(fingerY: pan.location(in: nil).y, viaScrollTarget: false)
            finish(velocity: pan.velocity(in: nil).y, cancelled: false)
        case .cancelled, .failed:
            finish(velocity: 0, cancelled: true)
        default:
            break
        }
    }

    @objc private func scrollPanDidChange(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began, .changed:
            guard isDragging, touchInScrollView, let recognizer else { return }
            process(fingerY: recognizer.location(in: nil).y, viaScrollTarget: true)
        case .ended, .cancelled, .failed:
            if shouldFreezeContent { freezeContent() }
        default:
            break
        }
    }

    private func process(fingerY: CGFloat, viaScrollTarget: Bool) {
        guard isDragging, controller.isDragging else { return }
        let dy = fingerY - lastFingerY
        defer { lastMoveViaScrollTarget = viaScrollTarget }
        guard dy != 0 else {
            if let written = lastWrittenOffsetY { writeOffset(written) }
            return
        }
        lastFingerY = fingerY
        guard touchInScrollView, let scrollView else {
            owner = .page
            controller.drag(by: dy)
            return
        }

        let start = lastOffsetY
        let minimum = Self.minOffset(of: scrollView)
        let progressBefore = controller.dragProgress
        let contentMovedItself = viaScrollTarget && lastMoveViaScrollTarget
            && scrollView.panGestureRecognizer.state == .changed
            && scrollView.panGestureRecognizer.numberOfTouches == 1
            && !shouldFreezeContent && !pageMovedInLastMove
        var written: CGFloat?

        if dy < 0 {
            let pageShare = min(-dy, max(1 - controller.dragProgress, 0) * controller.travelDistance)
            let contentShare = -dy - pageShare
            controller.drag(by: -pageShare)
            if contentShare > 0 {
                owner = .content
                frozenOffsetY = nil
                if !contentMovedItself {
                    written = min(start + contentShare, Self.maxOffset(of: scrollView))
                }
            } else {
                owner = .page
                frozenOffsetY = Self.clampedOffset(start, in: scrollView)
                written = frozenOffsetY
            }
        } else {
            let contentShare = min(dy, uploadIsOpen ? max(start - minimum, 0) : 0)
            var pageShare = dy - contentShare
            if pageShare > 0 {
                owner = .page
                let held = start - contentShare
                // A scroll bounce caught above the first row becomes page
                // movement, keeping the row's screen position continuous.
                pageShare += max(minimum - held, 0)
                frozenOffsetY = Self.clampedOffset(held, in: scrollView)
                written = frozenOffsetY
                controller.drag(by: pageShare)
            } else {
                owner = .content
                frozenOffsetY = nil
                if !contentMovedItself { written = start - contentShare }
            }
        }
        if let written { writeOffset(written) }
        lastWrittenOffsetY = written
        lastOffsetY = scrollView.contentOffset.y
        pageMovedInLastMove = controller.dragProgress != progressBefore
    }

    private func finish(velocity: CGFloat, cancelled: Bool) {
        guard isDragging else { return }
        let releasedOnContent = owner == .content && uploadIsOpen
        isDragging = false
        owner = .page
        lastWrittenOffsetY = nil
        pageMovedInLastMove = false
        lastMoveViaScrollTarget = false
        if controller.isDragging {
            controller.endDrag(velocity: releasedOnContent ? 0 : velocity, cancelled: cancelled)
        }
        // A release in the grid leaves its UIScrollView momentum alone.
        if !releasedOnContent, shouldFreezeContent { freezeContent() }
    }

    private func cancel() {
        if isDragging, controller.isDragging { controller.cancelDrag() }
        isDragging = false
        owner = .page
        lastWrittenOffsetY = nil
        pageMovedInLastMove = false
        lastMoveViaScrollTarget = false
        if shouldFreezeContent { freezeContent() }
    }

    private func reset() {
        finish(velocity: 0, cancelled: true)
        hasTouch = false
        touchInScrollView = false
        // Keep the offset lock until a partially dismissed page has left.
        // A fully open grid needs no observer and retains ordinary inertia.
        if uploadIsOpen { detach() }
    }

    private func attach(to candidate: UIScrollView) {
        scrollView = candidate
        candidate.panGestureRecognizer.addTarget(self, action: #selector(scrollPanDidChange(_:)))
        offsetObservation = candidate.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
            let old = change.oldValue
            let new = change.newValue
            MainActor.assumeIsolated {
                self?.offsetDidChange(from: old?.y, to: new?.y)
            }
        }
    }

    private func detach() {
        offsetObservation?.invalidate()
        offsetObservation = nil
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(scrollPanDidChange(_:)))
        scrollView = nil
        frozenOffsetY = nil
        touchInScrollView = false
    }

    private func offsetDidChange(from old: CGFloat?, to new: CGFloat?) {
        guard !isWritingOffset, let new, let scrollView else { return }
        guard shouldFreezeContent else {
            frozenOffsetY = nil
            return
        }
        let held = frozenOffsetY ?? (isDragging ? old ?? new : Self.clampedOffset(old ?? new, in: scrollView))
        frozenOffsetY = held
        if abs(new - held) > 0.001 { writeOffset(held, force: true) }
    }

    private func freezeContent() {
        guard let scrollView else { return }
        let held = Self.clampedOffset(frozenOffsetY ?? scrollView.contentOffset.y, in: scrollView)
        frozenOffsetY = held
        writeOffset(held, force: true)
    }

    private func writeOffset(_ y: CGFloat, force: Bool = false) {
        guard let scrollView, force || abs(scrollView.contentOffset.y - y) > 0.001 else { return }
        isWritingOffset = true
        defer { isWritingOffset = false }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
    }

    private static func verticalScrollView(containing view: UIView?, below root: UIView?) -> UIScrollView? {
        var current = view
        while let candidate = current {
            if let scroll = candidate as? UIScrollView, !(scroll is UITextView),
               scroll.alwaysBounceVertical || scroll.contentSize.height > scroll.bounds.height {
                return scroll
            }
            if candidate === root { break }
            current = candidate.superview
        }
        return nil
    }

    private static func minOffset(of scroll: UIScrollView) -> CGFloat { -scroll.adjustedContentInset.top }
    private static func maxOffset(of scroll: UIScrollView) -> CGFloat {
        max(scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height, minOffset(of: scroll))
    }
    private static func clampedOffset(_ y: CGFloat, in scroll: UIScrollView) -> CGFloat {
        min(max(y, minOffset(of: scroll)), maxOffset(of: scroll))
    }
}
