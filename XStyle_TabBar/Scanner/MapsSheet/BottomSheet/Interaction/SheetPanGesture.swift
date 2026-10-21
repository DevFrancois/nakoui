//
//  SheetPanGesture.swift
//  MapsIOS26BottomSheet
//

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The sheet's only drag gesture: one UIKit pan that recognizes alongside the sheet's vertical scroll view.
/// `SheetPanCoordinator` splits each touch move between the sheet and the content.
struct SheetPanGesture: UIGestureRecognizerRepresentable {
    let controller: SheetController

    func makeCoordinator(converter: CoordinateSpaceConverter) -> SheetPanCoordinator {
        SheetPanCoordinator(controller: controller)
    }

    func makeUIGestureRecognizer(context: Context) -> SheetPanRecognizer {
        let recognizer = SheetPanRecognizer()
        context.coordinator.configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: SheetPanRecognizer, context: Context) {
        context.coordinator.controller = controller
    }

    func handleUIGestureRecognizerAction(_ recognizer: SheetPanRecognizer, context: Context) {
        context.coordinator.sheetPanDidChange(recognizer)
    }
}

/// Reports UIKit's reset, so a touch that never became a drag lets go of a caught sheet.
final class SheetPanRecognizer: UIPanGestureRecognizer {
    var onReset: (() -> Void)?

    override func reset() {
        super.reset()
        onReset?()
    }
}

/// Delegate, per-move arbiter and content lock of the sheet pan.
///
/// Each touch move is split in window coordinates, which stay still while the sheet moves:
/// - finger up: the sheet rises until it reaches full; the rest of the move scrolls the content;
/// - finger down: at full, scrolled content returns to its top first; the rest moves the sheet down;
/// - a touch that started outside the scroll view (the header) always moves the sheet.
/// The content is frozen while the sheet owns the move and whenever the sheet is not at full. Three places
/// enforce it: the arbiter's own writes, a target on the scroll view's pan (it runs after UIScrollView moved
/// the content for that touch), and KVO on `contentOffset` (deceleration, bounce, early scroll moves).
/// The scroll view's delegate is never replaced: SwiftUI owns it.
final class SheetPanCoordinator: NSObject, UIGestureRecognizerDelegate {
    private enum Owner {
        case sheet
        case content
    }

    var controller: SheetController
    private weak var recognizer: SheetPanRecognizer?

    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    /// Offset held while the content is frozen; nil while it may scroll.
    private var frozenOffsetY: CGFloat?
    private var isWritingOffset = false

    private var isDragging = false
    private var owner: Owner = .sheet
    private var touchInScrollView = false
    /// The single touch this pan follows. Touches landing in the same event all see `numberOfTouches == 0`.
    private var hasTouch = false
    private var lastFingerY: CGFloat = 0
    /// Content offset at the end of the last processed move.
    private var lastOffsetY: CGFloat = 0
    /// Offset this coordinator wrote for the last move; re-asserted if UIScrollView moves after it.
    private var lastWrittenOffsetY: CGFloat?
    /// The sheet moved during the last move, so the scroll view's next own delta was measured in a moved frame.
    private var sheetMovedInLastMove = false
    /// The last move came through the scroll view's pan, after UIScrollView handled it.
    private var lastMoveViaScrollTarget = false

    init(controller: SheetController) {
        self.controller = controller
    }

    func configure(_ recognizer: SheetPanRecognizer) {
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        recognizer.onReset = { [weak self] in
            self?.recognizerDidReset()
        }
        self.recognizer = recognizer
    }

    private var shouldFreezeContent: Bool {
        (isDragging && owner == .sheet) || !controller.isAtOrAboveFull
    }

    /// The scroll view's pan follows this single touch, so its target processes the move after UIScrollView.
    private var isScrollPanTracking: Bool {
        guard touchInScrollView, let pan = scrollView?.panGestureRecognizer else { return false }
        return (pan.state == .began || pan.state == .changed) && pan.numberOfTouches == 1
    }

    // MARK: - Delegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        /// A dismissed sheet can't be caught on its way down.
        guard !isDragging, !hasTouch, gestureRecognizer.numberOfTouches == 0, controller.detent != .hidden else {
            return false
        }
        let location = touch.location(in: nil)
        /// Lock the content even for touches the sheet ignores.
        let enclosing = Self.verticalScrollView(containing: touch.view, below: gestureRecognizer.view)
        if let enclosing {
            attach(to: enclosing)
        }
        /// SwiftUI may attach the recognizer to a larger view: only the drawn surface counts.
        guard let surface = controller.geometry?.surface, surface.contains(location) else {
            SheetTrace.log("receive rejected y=\(location.y) view=\(Self.name(of: touch.view))")
            return false
        }
        touchInScrollView = enclosing != nil
        hasTouch = true
        /// Catch the sheet on touch down, like a native sheet, not when the pan begins 10 pt later.
        controller.hold()
        SheetTrace.log("receive y=\(location.y) view=\(Self.name(of: touch.view)) scroll=\(Self.name(of: enclosing))")
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: nil)
        return abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        guard let candidate = other.view as? UIScrollView,
              other === candidate.panGestureRecognizer,
              Self.scrollsVertically(candidate) else { return false }
        attach(to: candidate)
        /// Only this pan's own touch counts: the scroll pan may be following another finger.
        if !isDragging, !touchInScrollView, candidate.bounds.contains(gestureRecognizer.location(in: candidate)) {
            touchInScrollView = true
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool {
        /// Drags inside the content (sliders, custom pans) win over the sheet; scroll views share.
        other is UIPanGestureRecognizer && !(other.view is UIScrollView)
    }

    // MARK: - Sheet pan

    func sheetPanDidChange(_ pan: SheetPanRecognizer) {
        let fingerY = pan.location(in: nil).y
        let velocity = pan.velocity(in: nil).y
        switch pan.state {
        case .began:
            isDragging = true
            owner = .sheet
            lastFingerY = fingerY
            lastOffsetY = scrollView?.contentOffset.y ?? 0
            lastWrittenOffsetY = nil
            sheetMovedInLastMove = false
            lastMoveViaScrollTarget = false
            controller.beginDrag()
            SheetTrace.log("began top=\(controller.sheetTop ?? .nan) inScroll=\(touchInScrollView) offset=\(lastOffsetY)")
        case .changed:
            /// While the scroll view tracks this touch, its target processes the move after UIScrollView moved.
            guard !isScrollPanTracking else { return }
            process(fingerY: fingerY, velocity: velocity, viaScrollTarget: false)
        case .ended, .cancelled, .failed:
            /// Always processed, whatever the direction (SplitPaneKit drops upward releases on its scroll pan).
            process(fingerY: fingerY, velocity: velocity, viaScrollTarget: false)
            finish(velocity: pan.state == .ended ? velocity : 0)
        default:
            break
        }
    }

    // MARK: - Scroll view pan

    /// Added after UIScrollView's own handler, so it runs once the content has moved for this touch.
    @objc private func scrollPanDidChange(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began, .changed:
            guard isDragging, touchInScrollView, let recognizer else { return }
            /// The finger always comes from the sheet pan: the scroll pan averages every touch on it.
            process(
                fingerY: recognizer.location(in: nil).y,
                velocity: recognizer.velocity(in: nil).y,
                viaScrollTarget: true
            )
        case .ended, .cancelled, .failed:
            /// UIScrollView starts decelerating here; frozen content must not.
            if shouldFreezeContent {
                freezeContent()
            }
        default:
            break
        }
    }

    // MARK: - Arbiter

    private func process(fingerY: CGFloat, velocity: CGFloat, viaScrollTarget: Bool) {
        let dy = fingerY - lastFingerY
        defer {
            lastMoveViaScrollTarget = viaScrollTarget
        }
        guard dy != 0 else {
            reassertWrittenOffset()
            return
        }
        lastFingerY = fingerY

        guard touchInScrollView, let scrollView else {
            /// The header, or anything that doesn't scroll, always moves the sheet.
            owner = .sheet
            controller.drag(by: dy, velocity: velocity)
            return
        }

        let ownerBefore = owner
        let start = lastOffsetY
        let minimum = Self.minOffsetY(of: scrollView)
        let sheetBefore = controller.sheetTop ?? 0
        let scrollPan = scrollView.panGestureRecognizer
        /// UIScrollView applied this move itself only if the content was free, its pan was already following this
        /// touch, and the sheet (its frame) didn't move since its previous delta.
        let contentMovedItself = viaScrollTarget
            && lastMoveViaScrollTarget
            && scrollPan.state == .changed
            && scrollPan.numberOfTouches == 1
            && !shouldFreezeContent
            && !sheetMovedInLastMove
        var written: CGFloat?

        if dy < 0 {
            /// Finger up: the sheet rises to full first; the rest scrolls the content.
            let sheetShare = min(-dy, controller.distanceToFull)
            let contentShare = -dy - sheetShare
            controller.drag(by: -sheetShare, velocity: sheetShare > 0 ? velocity : 0)
            if contentShare > 0 {
                if owner == .sheet {
                    controller.didReachFullDuringDrag()
                }
                owner = .content
                frozenOffsetY = nil
                if !contentMovedItself {
                    /// No lower clamp: overscroll left from a bounce resolves through UIScrollView's own bounce.
                    written = min(start + contentShare, Self.maxOffsetY(of: scrollView))
                }
            } else {
                owner = .sheet
                let held = Self.clampedOffsetY(start, in: scrollView)
                frozenOffsetY = held
                written = held
            }
        } else {
            /// Finger down: at full, scrolled content returns to its top first; the rest moves the sheet.
            let scrolled = controller.isAtOrAboveFull ? max(start - minimum, 0) : 0
            let contentShare = min(dy, scrolled)
            var sheetShare = dy - contentShare
            if sheetShare > 0 {
                owner = .sheet
                var held = start - contentShare
                if held < minimum {
                    /// Content caught past its top: snap it to the top and move the sheet by the same amount,
                    /// so nothing moves on screen and no gap stays above the first row.
                    sheetShare += minimum - held
                    held = minimum
                }
                held = Self.clampedOffsetY(held, in: scrollView)
                frozenOffsetY = held
                written = held
                controller.drag(by: sheetShare, velocity: velocity)
            } else {
                owner = .content
                frozenOffsetY = nil
                if !contentMovedItself {
                    written = start - contentShare
                }
                controller.drag(by: 0, velocity: 0)
            }
        }

        if let written {
            writeOffset(written)
        }
        lastWrittenOffsetY = written
        lastOffsetY = scrollView.contentOffset.y
        let sheetDelta = (controller.sheetTop ?? 0) - sheetBefore
        sheetMovedInLastMove = sheetDelta != 0
        if owner != ownerBefore {
            SheetTrace.log("owner → \(owner) dy=\(dy) sheetΔ=\(sheetDelta) offset \(start)→\(lastOffsetY)")
        }
    }

    /// A same-event callback after our write (e.g. the scroll pan beginning late) must not add its own move.
    private func reassertWrittenOffset() {
        guard let lastWrittenOffsetY, let scrollView,
              abs(scrollView.contentOffset.y - lastWrittenOffsetY) > 0.001 else { return }
        writeOffset(lastWrittenOffsetY)
        lastOffsetY = lastWrittenOffsetY
    }

    private func finish(velocity: CGFloat) {
        guard isDragging else { return }
        let releasedOnContent = touchInScrollView && owner == .content
        isDragging = false
        owner = .sheet
        lastWrittenOffsetY = nil
        sheetMovedInLastMove = false
        lastMoveViaScrollTarget = false
        if releasedOnContent {
            /// The content keeps its momentum; the sheet stays at full.
            controller.endDragOnContent()
        } else {
            controller.endDrag(velocity: velocity)
            if touchInScrollView, shouldFreezeContent {
                freezeContent()
            }
        }
    }

    func recognizerDidReset() {
        if isDragging {
            finish(velocity: 0)
        }
        controller.releaseHold()
        touchInScrollView = false
        hasTouch = false
    }

    // MARK: - Content lock

    private func attach(to candidate: UIScrollView) {
        guard candidate !== scrollView else { return }
        detach()
        scrollView = candidate
        candidate.panGestureRecognizer.addTarget(self, action: #selector(scrollPanDidChange(_:)))
        offsetObservation = candidate.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
            let old = change.oldValue
            let new = change.newValue
            MainActor.assumeIsolated {
                self?.contentOffsetDidChange(from: old, to: new)
            }
        }
        SheetTrace.log("attach \(Self.name(of: candidate))")
    }

    private func detach() {
        offsetObservation?.invalidate()
        offsetObservation = nil
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(scrollPanDidChange(_:)))
        scrollView = nil
        frozenOffsetY = nil
    }

    /// KVO: undo any move the content makes while it is frozen (its own pan, deceleration, bounce).
    private func contentOffsetDidChange(from old: CGPoint?, to new: CGPoint?) {
        guard !isWritingOffset, let scrollView, let new else { return }
        guard shouldFreezeContent else {
            frozenOffsetY = nil
            return
        }
        let held: CGFloat
        if let frozenOffsetY {
            held = frozenOffsetY
        } else if isDragging, touchInScrollView {
            /// Caught mid-bounce: stay where it is drawn. The first move hands the overscroll to the sheet.
            held = old?.y ?? new.y
        } else {
            held = Self.clampedOffsetY(old?.y ?? new.y, in: scrollView)
        }
        frozenOffsetY = held
        if abs(new.y - held) > 0.001 {
            writeOffset(held, force: true)
        }
    }

    private func freezeContent() {
        guard let scrollView else { return }
        let held = Self.clampedOffsetY(frozenOffsetY ?? scrollView.contentOffset.y, in: scrollView)
        frozenOffsetY = held
        writeOffset(held, force: true)
    }

    /// Non-animated, so it also stops a deceleration in flight. `force` writes even when already there.
    private func writeOffset(_ y: CGFloat, force: Bool = false) {
        guard let scrollView, force || abs(scrollView.contentOffset.y - y) > 0.001 else { return }
        isWritingOffset = true
        defer {
            isWritingOffset = false
        }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
    }

    // MARK: - Helpers

    private static func verticalScrollView(containing view: UIView?, below root: UIView?) -> UIScrollView? {
        var current = view
        while let candidate = current, candidate !== root {
            if let scrollView = candidate as? UIScrollView, scrollsVertically(scrollView) {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    private static func scrollsVertically(_ scrollView: UIScrollView) -> Bool {
        !(scrollView is UITextView)
            && (scrollView.alwaysBounceVertical || scrollView.contentSize.height > scrollView.bounds.height)
    }

    private static func minOffsetY(of scrollView: UIScrollView) -> CGFloat {
        -scrollView.adjustedContentInset.top
    }

    private static func maxOffsetY(of scrollView: UIScrollView) -> CGFloat {
        max(
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height,
            minOffsetY(of: scrollView)
        )
    }

    private static func clampedOffsetY(_ y: CGFloat, in scrollView: UIScrollView) -> CGFloat {
        clip(value: y, lower: minOffsetY(of: scrollView), upper: maxOffsetY(of: scrollView))
    }

    private static func name(of view: UIView?) -> String {
        view.map { String(describing: type(of: $0)) } ?? "nil"
    }
}
