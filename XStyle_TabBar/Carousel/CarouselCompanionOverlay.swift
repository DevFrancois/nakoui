import UIKit

/// Owns cached companions without a display link or a SwiftUI update per frame.
final class CarouselCompanionOverlay {
    /// A prompt appears as its card arrives near the destination, not at the start
    /// of a horizontal handoff. Use the destination width, independent of in-flight scale.
    static func revealIndex(frame: CarouselFrame, focusedIndex: Int?, focusedTarget: CarouselPose?,
                            wheelIndex: Int?, count: Int, selectedOnly: Bool) -> Int? {
        guard count > 0, frame.size.width > 0 else { return nil }
        if let focusedIndex {
            guard (0..<count).contains(focusedIndex),
                  let card = frame.promoted.first(where: { $0.index == focusedIndex }) else { return nil }
            let width = focusedTarget?.width ?? card.pose.width
            guard width.isFinite, width > 0,
                  abs(card.pose.x - Double(frame.size.width) / 2) < 0.3 * (width + 20) else { return nil }
            return focusedIndex
        }
        guard !selectedOnly, let wheelIndex, (0..<count).contains(wheelIndex),
              abs(CarouselGeometry.relative(wheelIndex, position: frame.position, count: count)) < 0.3 else { return nil }
        return wheelIndex
    }

    /// A submission owns the geometry it encoded, even while simulation keeps
    /// advancing before Metal becomes ready to present it.
    struct PresentationSnapshot {
        fileprivate struct Item {
            let index: Int
            let viewIdentity: ObjectIdentifier
            let content: CarouselCompanionContent
            let size: CGSize
            let motion: CarouselCompanionMotion
        }

        let revision: UInt64
        fileprivate let sequence: UInt64
        fileprivate let interactive: Bool
        fileprivate let items: [Item]
    }

    private final class Entry {
        let view: FeatureCompanionBubble
        var content: CarouselCompanionContent
        var motion: CarouselCompanionMotion
        var presentedMotion: CarouselCompanionMotion?
        // Content can change while an encoded frame awaits presentation. Measure
        // the new text without changing the bubble that is still on screen.
        var measurementView: FeatureCompanionBubble?
        var needsInteractionUpdate = false
        var size: CGSize = .zero
        var anchorInputs: AnchorInputs?
        var cachedAnchor: CGPoint = .zero
        init(content: CarouselCompanionContent, anchor: CGPoint) {
            self.content = content
            view = FeatureCompanionBubble(content: content)
            motion = CarouselCompanionMotion(anchor: anchor)
        }
    }

    private struct AnchorInputs: Equatable {
        var pose: CarouselPose
        var bubbleSize: CGSize
        var content: CarouselCompanionContent
        var frameSize: CGSize
        var padding: Double
        var card3D: CarouselConfiguration.Card3D
        var safeAreaInsets: UIEdgeInsets
        var parallax: Double
    }

    var requestFrame: (() -> Void)?
    var ownershipBegan: (() -> Void)?
    var ownershipEnded: (() -> Void)?
    var presentationInvalidated: (() -> Void)?
    private(set) var presentationRevision: UInt64 = 0
    private var nextPresentationSequence: UInt64 = 0
    private var presentedSequence: UInt64 = 0
    private var configuration = CarouselCompanionConfiguration()
    private var contentProvider: ((Int) -> CarouselCompanionContent?)?
    private var entries: [Int: Entry] = [:]
    private var activeIndex: Int? {
        didSet {
            if oldValue != activeIndex {
                orderNeedsUpdate = true
                invalidatePresentation()
            }
        }
    }
    private var interactionIndex: Int? {
        didSet { if oldValue != interactionIndex { orderNeedsUpdate = true } }
    }
    private var drainingView: FeatureCompanionBubble?
    private var suppliedContentIndex: Int?
    private var returningManipulations = Set<Int>()
    private var presentedOrder: [Int] = []
    private var cachedOrder: [Int] = []
    private var orderNeedsUpdate = false
    private weak var host: UIView?

    var needsAnimation: Bool { entries.values.contains { $0.motion.needsAnimation } }
    var isInteracting: Bool { interactionIndex != nil || drainingView?.hasTouches == true }
    var isBlockingAutoplay: Bool { isInteracting || !returningManipulations.isEmpty }
    var interactionView: UIView? { interactionIndex.flatMap { entries[$0]?.view } ?? drainingView }
    /// A cached, hidden prompt has no geometry to synchronize with the cards.
    /// Keep synchronization until the final hide has actually been presented.
    var requiresSynchronizedPresentation: Bool {
        entries.values.contains {
            !$0.motion.isHiddenAndSettled || ($0.view.superview != nil && !$0.view.isHidden)
        }
    }
    var visibleAccessibilityElements: [Any] {
        presentedOrder.reversed().compactMap { index in
            guard let view = entries[index]?.view, !view.isHidden, view.alpha > 0.05 else { return nil }
            return view
        }
    }

    func configure(content: ((Int) -> CarouselCompanionContent?)?, configuration: CarouselCompanionConfiguration) {
        let changed = self.configuration != configuration
        self.configuration = configuration
        contentProvider = content
        guard configuration.isEnabled, content != nil else { removeAll(); return }
        if !configuration.isInteractive { cancelInteraction() }
        if changed {
            invalidatePresentation()
            for entry in entries.values {
                // Input ownership changes immediately; visible text and geometry
                // still wait for their captured card presentation transaction.
                entry.view.isUserInteractionEnabled = configuration.isInteractive
                entry.needsInteractionUpdate = true
            }
            requestFrame?()
        }
    }

    func advance(frame: CarouselFrame, activeIndex: Int?, dragging: Bool, dt: Double) {
        guard configuration.isEnabled, let contentProvider else { return }
        if let interactionIndex, interactionIndex != activeIndex { cancelInteraction() }
        self.activeIndex = activeIndex
        var showingIndex: Int?
        if let index = activeIndex, let content = contentProvider(index), !content.prompt.isEmpty,
           let card = frame.promoted.first(where: { $0.index == index }) ?? frame.wheel.first(where: { $0.index == index }) {
            showingIndex = index
            let entry: Entry
            if let existing = entries[index] { entry = existing }
            else {
                entry = Entry(content: content, anchor: CGPoint(x: card.pose.x, y: card.pose.y))
                configureCallbacks(entry, index: index)
                entries[index] = entry
                orderNeedsUpdate = true
            }
            if entry.content != content {
                entry.content = content
                if let measurementView = entry.measurementView {
                    measurementView.update(content: content, interactive: false)
                } else {
                    entry.measurementView = FeatureCompanionBubble(content: content)
                }
                invalidatePresentation()
            }
            let maximumWidth = min(280, max(120, frame.size.width - 48))
            let size = (entry.measurementView ?? entry.view).preferredSize(maximumWidth: maximumWidth)
            entry.size = size
            let anchor = companionAnchor(for: card.pose, entry: entry, frame: frame)
            // New companions start at their anchor, so only the pop animates on first appearance.
            if entry.view.superview == nil && entry.motion.presence.value == 0 {
                entry.motion = CarouselCompanionMotion(anchor: anchor)
            }
            entry.motion.retarget(anchor: anchor, visible: !dragging || index == interactionIndex)
        }
        if suppliedContentIndex != showingIndex {
            suppliedContentIndex = showingIndex
            invalidatePresentation()
        }
        for (index, entry) in entries {
            if index != showingIndex && entry.motion.isHiddenAndSettled {
                returningManipulations.remove(index)
                continue
            }
            entry.motion.constrainInteraction(to: interactionBounds(size: entry.size, motion: entry.motion, frame: frame))
            if index != showingIndex {
                entry.motion.retarget(anchor: entry.motion.anchor, visible: index == interactionIndex)
            }
            entry.motion.advance(by: dt, configuration: configuration, cardIsDragging: dragging,
                                 reduceMotion: UIAccessibility.isReduceMotionEnabled)
            if !entry.motion.needsAnimation { returningManipulations.remove(index) }
        }
    }

    /// Capture at command encoding, after simulation has produced the card frame.
    /// No geometry or content is read from mutable motion when this is applied.
    func capturePresentation() -> PresentationSnapshot {
        nextPresentationSequence &+= 1
        return PresentationSnapshot(revision: presentationRevision, sequence: nextPresentationSequence,
            interactive: configuration.isInteractive, items: orderedIndices.compactMap { index in
                guard let entry = entries[index] else { return nil }
                return PresentationSnapshot.Item(index: index, viewIdentity: ObjectIdentifier(entry.view),
                    content: entry.content, size: entry.size, motion: entry.motion)
            })
    }

    func isPresentationValid(_ snapshot: PresentationSnapshot) -> Bool {
        guard snapshot.revision == presentationRevision, snapshot.sequence >= presentedSequence else { return false }
        return snapshot.items.allSatisfy { item in
            guard let entry = entries[item.index] else { return false }
            return ObjectIdentifier(entry.view) == item.viewIdentity && entry.content == item.content
        }
    }

    /// Shares the card transaction when it redraws; otherwise the host commits
    /// this over the last confirmed card image using the same display clock.
    func applyPresentation(in host: UIView) {
        applyPresentation(capturePresentation(), in: host)
    }

    /// Returns false without touching UIKit when an interruption superseded the
    /// packet, or a newer packet has already presented. Callers reject its card
    /// drawables in the same transaction rather than mixing two frame states.
    @discardableResult
    func applyPresentation(_ snapshot: PresentationSnapshot, in host: UIView) -> Bool {
        guard isPresentationValid(snapshot) else { return false }
        self.host = host
        let order = snapshot.items.map(\.index)
        let topmost = order.last.flatMap { entries[$0]?.view }
        let reorder = presentedOrder != order || (topmost != nil && host.subviews.last !== topmost)
        for item in snapshot.items {
            guard let entry = entries[item.index] else { continue }
            let view = entry.view
            // Preserve a cached view (and any touch-draining ownership) without
            // running layout, transform, or accessibility updates every frame.
            if view.isHidden && item.motion.isHiddenAndSettled { continue }
            if view.superview !== host { host.addSubview(view) }
            else if reorder { host.bringSubviewToFront(view) }
            if entry.measurementView != nil || entry.needsInteractionUpdate ||
                view.isUserInteractionEnabled != snapshot.interactive {
                view.update(content: item.content, interactive: snapshot.interactive)
                entry.measurementView = nil
                entry.needsInteractionUpdate = false
            }
            let size = item.size
            if view.bounds.size != size {
                view.bounds = CGRect(origin: .zero, size: size)
                view.setNeedsLayout()
            }
            if view.layer.needsLayout() { view.layoutIfNeeded() }
            let center = CGPoint(x: item.motion.position.x,
                                 y: item.motion.position.y + item.motion.renderedRise)
            if view.center != center { view.center = center }
            let scale = item.motion.renderedScale
            let transform = CGAffineTransform(rotationAngle: item.motion.rotation.value).scaledBy(x: scale, y: scale)
            if view.transform != transform { view.transform = transform }
            let opacity = item.motion.renderedOpacity
            if view.alpha != opacity { view.alpha = opacity }
            let hidden = item.motion.isHiddenAndSettled
            if view.isHidden != hidden { view.isHidden = hidden }
            view.accessibilityElementsHidden = hidden || opacity < 0.05
            entry.presentedMotion = item.motion
        }
        presentedOrder = order
        presentedSequence = snapshot.sequence
        return true
    }

    private func invalidatePresentation() {
        presentationRevision &+= 1
        presentationInvalidated?()
    }

    func hitView(at point: CGPoint, in host: UIView) -> UIView? {
        // Once owned, additional fingers belong to this same companion even outside its shape.
        if let interactionView { return interactionView }
        guard configuration.isEnabled, configuration.isInteractive else { return nil }
        for index in presentedOrder.reversed() {
            guard let view = entries[index]?.view, view.superview === host else { continue }
            if view.point(inside: view.convert(point, from: host), with: nil) { return view }
        }
        return nil
    }

    func containsDisplayedPoint(_ point: CGPoint, in host: UIView) -> Bool { hitView(at: point, in: host) != nil }

    func cancelInteraction(preservingTouchOwnership: Bool = true) {
        if !preservingTouchOwnership { drainingView?.cancelTouches() }
        guard let index = interactionIndex, let entry = entries[index] else { return }
        entry.view.cancelTouches(preservingOwnership: preservingTouchOwnership)
        if interactionIndex != nil { finishInteraction(index: index, cancelled: true) }
    }

    func removeAll(preservingTouchOwnership: Bool = true) {
        invalidatePresentation()
        cancelInteraction(preservingTouchOwnership: preservingTouchOwnership)
        for entry in entries.values {
            if entry.view === drainingView {
                entry.view.alpha = 0
                entry.view.accessibilityElementsHidden = true
            } else { entry.view.removeFromSuperview() }
        }
        entries.removeAll()
        presentedOrder.removeAll()
        cachedOrder.removeAll()
        orderNeedsUpdate = false
        returningManipulations.removeAll()
        suppliedContentIndex = nil
        activeIndex = nil
    }

    private var orderedIndices: [Int] {
        guard orderNeedsUpdate else { return cachedOrder }
        cachedOrder = entries.keys.sorted {
            if $0 == interactionIndex { return false }
            if $1 == interactionIndex { return true }
            if $0 == activeIndex { return false }
            if $1 == activeIndex { return true }
            return $0 < $1
        }
        orderNeedsUpdate = false
        return cachedOrder
    }

    private func companionAnchor(for pose: CarouselPose, entry: Entry, frame: CarouselFrame) -> CGPoint {
        let safe = host?.safeAreaInsets ?? .zero
        let requestedParallax = configuration.parallax.isFinite ? min(0.75, max(0, configuration.parallax)) : 0.18
        let parallax = UIAccessibility.isReduceMotionEnabled || !configuration.motionEnabled ? 0 : requestedParallax
        let size = entry.size
        let content = entry.content
        let inputs = AnchorInputs(pose: pose, bubbleSize: size, content: content, frameSize: frame.size,
            padding: frame.glass.padding, card3D: frame.card3D, safeAreaInsets: safe, parallax: parallax)
        if entry.anchorInputs == inputs { return entry.cachedAnchor }
        let fraction: Double
        switch content.alignment {
        case .leading: fraction = 0.25
        case .center: fraction = 0.5
        case .trailing: fraction = 0.75
        }
        let geometry = CarouselSceneCardGeometry(pose: pose, padding: frame.glass.padding,
            card3D: frame.card3D, camera: CarouselSceneCamera(size: frame.size))
        let leftCorner = geometry.project(SIMD3(-geometry.half.x, geometry.half.y, 0))
        let rightCorner = geometry.project(SIMD3(geometry.half.x, geometry.half.y, 0))
        let edge = leftCorner + (rightCorner - leftCorner) * fraction
        let displacement = (pose.x - Double(frame.size.width) / 2) * parallax
        let x = CGFloat(edge.x + 24 * tanh(displacement / 24))
        let gap = content.gap.isFinite ? max(0, content.gap) : 18
        let y = CGFloat(edge.y) + gap
        let left = safe.left + 20 + size.width / 2
        let right = max(left, frame.size.width - safe.right - 20 - size.width / 2)
        let top = safe.top + 76 + size.height / 2
        let bottom = max(top, frame.size.height - safe.bottom - 76 - size.height / 2)
        let anchor = CGPoint(x: min(right, max(left, x)), y: min(bottom, max(top, y)))
        entry.anchorInputs = inputs
        entry.cachedAnchor = anchor
        return anchor
    }

    private func interactionBounds(size: CGSize, motion: CarouselCompanionMotion, frame: CarouselFrame) -> CGRect {
        let safe = host?.safeAreaInsets ?? .zero
        let scale = max(0.3, motion.scale.value)
        let cosine = abs(cos(motion.rotation.value)), sine = abs(sin(motion.rotation.value))
        let halfWidth = (size.width * cosine + size.height * sine) * scale / 2
        let halfHeight = (size.width * sine + size.height * cosine) * scale / 2
        let left = min(frame.size.width / 2, safe.left + 16 + halfWidth)
        let right = max(left, frame.size.width - safe.right - 16 - halfWidth)
        let top = min(frame.size.height / 2, safe.top + 16 + halfHeight)
        let bottom = max(top, frame.size.height - safe.bottom - 16 - halfHeight)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private func configureCallbacks(_ entry: Entry, index: Int) {
        entry.view.accessibilityIdentifier = "feature-companion-\(index)"
        entry.view.update(content: entry.content, interactive: configuration.isInteractive)
        entry.view.onContentSizeChanged = { [weak self] in
            self?.invalidatePresentation()
            self?.requestFrame?()
        }
        entry.view.onTouchesDrained = { [weak self, weak view = entry.view] in
            guard let self, self.drainingView === view else { return }
            let draining = self.drainingView
            self.drainingView = nil
            if !self.entries.values.contains(where: { $0.view === draining }) { draining?.removeFromSuperview() }
            self.ownershipEnded?()
            self.requestFrame?()
        }
        entry.view.onInteractionBegan = { [weak self] time in
            guard let self, self.configuration.isInteractive, !self.isInteracting,
                  let entry = self.entries[index] else { return }
            self.invalidatePresentation()
            self.interactionIndex = index
            self.returningManipulations.remove(index)
            if let shown = entry.presentedMotion { entry.motion = shown }
            entry.motion.beginInteraction(at: time)
            self.ownershipBegan?()
            self.requestFrame?()
        }
        entry.view.onInteractionChanged = { [weak self] translation, scale, rotation, pivot, time in
            guard let self, self.interactionIndex == index, let entry = self.entries[index] else { return }
            entry.motion.manipulate(translation: translation, scaleFactor: scale, rotationDelta: rotation,
                                    pivot: pivot, at: time)
            self.requestFrame?()
        }
        entry.view.onInteractionEnded = { [weak self] cancelled in
            self?.finishInteraction(index: index, cancelled: cancelled)
        }
        entry.view.onReset = { [weak self] in
            guard let self, let entry = self.entries[index] else { return }
            if self.interactionIndex == index { self.cancelInteraction() }
            self.invalidatePresentation()
            entry.motion.reset()
            self.returningManipulations.insert(index)
            self.requestFrame?()
        }
        entry.view.onNudge = { [weak self] velocity in
            guard let self, let entry = self.entries[index] else { return }
            self.invalidatePresentation()
            entry.motion.nudge(horizontal: velocity)
            self.returningManipulations.insert(index)
            self.requestFrame?()
        }
    }

    private func finishInteraction(index: Int, cancelled: Bool) {
        guard interactionIndex == index, let entry = entries[index] else { return }
        invalidatePresentation()
        entry.motion.endInteraction(cancelled: cancelled)
        returningManipulations.insert(index)
        interactionIndex = nil
        if entry.view.hasTouches { drainingView = entry.view }
        else { ownershipEnded?() }
        requestFrame?()
    }
}
