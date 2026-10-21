//
//  SheetController.swift
//  MapsIOS26BottomSheet
//
//  The next-detent rule (70 pt / 300 pt/s, 1 % tolerance) is adapted from SplitPaneKit,
//  Copyright (c) 2025 Joseph Smith. MIT — see THIRD_PARTY_NOTICES.md.
//  Unlike SplitPaneKit, the direction comes from whichever threshold fired.
//

import CoreGraphics
import Foundation
import Observation

/// Single source of truth for the custom sheet's position.
///
/// `sheetTop` is written by the drag (once per touch move) and by a Wave spring (once per display frame),
/// never through SwiftUI animations. `SheetContainer` and `TopPaneView` both read it, so the sheet and the
/// pane render in the same SwiftUI update.
@Observable
final class SheetController {
    /// Displayed sheet top in window coordinates; nil until the canvas is measured.
    private(set) var sheetTop: CGFloat? = nil
    private(set) var canvas: PaneCanvas = .zero
    /// Where the sheet rests, or is settling to.
    private(set) var detent: SheetDetent {
        didSet {
            if detent != oldValue {
                fadeSurface()
            }
        }
    }
    /// The full-sheet surface: 0 on glass, 1 once opaque with opaque cards. Like Apple Maps, it fades over about 0.2 s
    /// when the target detent becomes full or leaves it, not with the sheet's position.
    private(set) var surfaceProgress: CGFloat
    /// Incremented when a detent change should play a haptic.
    private(set) var feedbackTrigger = 0

    let metrics = SheetMetrics.current

    @ObservationIgnored var reduceMotion = false
    /// Debug settings: settle with the bouncy spring, and let the pane follow the overshoot.
    @ObservationIgnored var bounces = true
    @ObservationIgnored var paneFollowsBounce = true
    /// Displayed sheet velocity in pt/s, positive downward; drives the pane's stretch.
    @ObservationIgnored var onVelocityChange: ((CGFloat) -> Void)?
    @ObservationIgnored private(set) var isDragging = false

    /// Position before rubber-banding: the finger's while dragging, the spring's while settling.
    @ObservationIgnored private var rawTop: CGFloat = 0
    @ObservationIgnored private var dragStartTop: CGFloat = 0
    /// A touch stopped the spring and no drag has started yet.
    @ObservationIgnored private var isHeld = false
    /// Where the running settle started, which tells its overshoot from its approach; nil otherwise.
    @ObservationIgnored private var settleOrigin: CGFloat?

    private let spring = SpringAnimator<CGFloat>(spring: SheetSprings.bouncy)
    private let surfaceSpring = SpringAnimator<CGFloat>(spring: SheetSprings.surface)

    init(initialDetent: SheetDetent? = nil) {
        let detent = initialDetent ?? Self.launchDetent
        self.detent = detent
        surfaceProgress = detent == .full ? 1 : 0
        surfaceSpring.value = surfaceProgress
        surfaceSpring.target = surfaceProgress
        spring.valueChanged = { [weak self] value in
            self?.springDidChange(value)
        }
        surfaceSpring.valueChanged = { [weak self] value in
            /// The spring is critically damped; clamp only its last rounding.
            self?.surfaceProgress = clipUnit(value: value)
        }
    }

    // MARK: - Geometry

    var tops: DetentValues {
        metrics.tops(for: canvas)
    }

    /// Surface geometry for the displayed position. Reading it subscribes to every move.
    var geometry: SheetGeometry? {
        guard let sheetTop, canvas.size.height > 0 else { return nil }
        return SheetGeometry(sheetTop: sheetTop, canvas: canvas, metrics: metrics, tops: tops)
    }

    /// The sheet top the pane follows: `sheetTop`, or held at the destination while a settle overshoots it
    /// with `paneFollowsBounce` off. Reading it subscribes to every move.
    var paneSheetTop: CGFloat? {
        guard let sheetTop, !paneFollowsBounce, let settleOrigin, spring.state == .running else { return sheetTop }
        let destination = tops[detent]
        return settleOrigin < destination ? min(sheetTop, destination) : max(sheetTop, destination)
    }

    /// At full, or above it while rubber-banding: the only place the content may scroll.
    var isAtOrAboveFull: Bool {
        guard let sheetTop, canvas.size.height > 0 else { return false }
        return sheetTop <= tops.full + SheetTuning.edgeTolerance
    }

    /// How far the sheet can still rise before it reaches full.
    var distanceToFull: CGFloat {
        guard let sheetTop, canvas.size.height > 0 else { return 0 }
        return max(sheetTop - tops.full, 0)
    }

    func updateCanvas(_ newCanvas: PaneCanvas) {
        guard newCanvas != canvas, newCanvas.size.height > 0 else { return }
        canvas = newCanvas
        guard !isDragging else { return }
        let destination = tops[detent]
        if spring.state == .running {
            spring.target = destination
        } else {
            isHeld = false
            place(at: destination)
        }
    }

    // MARK: - Touches (SheetPanCoordinator)

    /// Touch down on the sheet: stop it where it is drawn.
    func hold() {
        guard !isDragging, spring.state == .running else { return }
        spring.stop()
        isHeld = true
        settleOrigin = nil
        onVelocityChange?(0)
        SheetTrace.log("hold top=\(sheetTop ?? .nan)")
    }

    /// The touch ended without becoming a drag: finish the interrupted settle.
    func releaseHold() {
        guard isHeld, !isDragging else { return }
        isHeld = false
        SheetTrace.log("releaseHold top=\(sheetTop ?? .nan) → \(detent)")
        settle(to: detent, velocity: 0)
    }

    func beginDrag() {
        guard let sheetTop else { return }
        if spring.state == .running {
            spring.stop()
        }
        isHeld = false
        isDragging = true
        settleOrigin = nil
        dragStartTop = sheetTop
    }

    /// Moves the sheet by the finger's share of one touch move, in window points.
    func drag(by delta: CGFloat, velocity: CGFloat) {
        guard isDragging, canvas.size.height > 0 else { return }
        let tops = tops
        var proposed = rawTop + delta
        /// The arbiter hands the content exactly the move past full: land on full without drift.
        if abs(proposed - tops.full) < 0.001 {
            proposed = tops.full
        }
        rawTop = proposed
        setDisplayedTop(displayedTop(for: proposed))
        onVelocityChange?(delta == 0 ? 0 : displayedVelocity(raw: proposed, velocity: velocity))
    }

    /// The finger carried the sheet up to full and the content takes the rest of the move.
    /// Click into full now, like the native sheet, and measure later travel from full.
    func didReachFullDuringDrag() {
        guard isDragging else { return }
        dragStartTop = tops.full
        guard detent != .full else { return }
        detent = .full
        playDetentFeedback()
    }

    /// Release while the sheet owned the drag: pick the next detent and spring to it.
    func endDrag(velocity: CGFloat) {
        guard isDragging else { return }
        isDragging = false
        let target = nextDetent(releaseVelocity: velocity)
        SheetTrace.log("release v=\(velocity) → \(target)")
        settle(to: target, velocity: velocity)
    }

    /// Release while the content owned the drag: the sheet is at full and stays there.
    func endDragOnContent() {
        guard isDragging else { return }
        isDragging = false
        settle(to: .full, velocity: 0)
    }

    // MARK: - Programmatic moves

    /// Tap on the top pane. A hidden sheet stays hidden: there is nothing to show.
    func collapse() {
        guard !isDragging, detent != .hidden else { return }
        settle(to: .collapsed, velocity: spring.state == .running ? spring.velocity : 0)
    }

    /// Springs from the current position and velocity to `target`.
    func settle(to target: SheetDetent, velocity: CGFloat) {
        if target != detent {
            /// Like a native sheet, no detent haptic when it is presented or dismissed.
            let isPresentation = target == .hidden || detent == .hidden
            detent = target
            if !isPresentation {
                playDetentFeedback()
            }
        }
        guard sheetTop != nil, canvas.size.height > 0 else { return }
        isHeld = false
        let destination = tops[target]
        let injected = clip(
            value: velocity,
            lower: -SheetTuning.maxReleaseVelocity,
            upper: SheetTuning.maxReleaseVelocity
        )
        if abs(rawTop - destination) < 0.01, abs(injected) < 1 {
            if spring.state == .running {
                spring.stop()
            }
            settleOrigin = nil
            place(at: destination)
            onVelocityChange?(0)
            return
        }
        settleOrigin = rawTop
        /// A dismissal doesn't bounce: swinging back above the screen's edge would draw the sheet again.
        spring.spring = target == .hidden ? dismissalSpring : currentSpring
        spring.target = destination
        spring.restart(value: rawTop, velocity: injected)
    }

    // MARK: - Snap rule

    /// SplitPaneKit's rule: past 70 pt of travel or 300 pt/s, the nearest detent beyond the sheet in that
    /// direction (never skipping one); otherwise the current detent.
    private func nextDetent(releaseVelocity velocity: CGFloat) -> SheetDetent {
        guard let current = sheetTop else { return detent }
        let travel = current - dragStartTop
        let isFast = abs(velocity) > SheetTuning.nextDetentVelocity
        guard isFast || abs(travel) > SheetTuning.nextDetentDistance else {
            return detent
        }
        let tops = tops
        let tolerance = canvas.size.height * SheetTuning.nextDetentTolerance
        let movingDown = isFast ? velocity > 0 : travel > 0
        /// `allCases` runs from the lowest detent (largest top) to the highest.
        if movingDown {
            let next = SheetDetent.allCases.last { tops[$0] > current + tolerance } ?? .hidden
            /// Dismissing closes the result: only a release clearly below collapsed does it.
            return next == .hidden && current < tops.collapsed + tolerance ? .collapsed : next
        }
        return SheetDetent.allCases.first { tops[$0] < current - tolerance } ?? .full
    }

    // MARK: - Position

    private func springDidChange(_ value: CGFloat) {
        guard !isDragging else { return }
        rawTop = value
        setDisplayedTop(displayedTop(for: value))
        let velocity = value == spring.target ? 0 : spring.velocity
        onVelocityChange?(displayedVelocity(raw: value, velocity: velocity))
    }

    private func place(at top: CGFloat) {
        rawTop = top
        setDisplayedTop(displayedTop(for: top))
    }

    /// Writes only real changes: every write invalidates the sheet and the pane.
    private func setDisplayedTop(_ top: CGFloat) {
        if sheetTop != top {
            sheetTop = top
        }
    }

    /// Rubber-banded to the detent range; drags and spring overshoots past the ends both go through it.
    /// The range ends at hidden, so below collapsed the sheet follows the finger toward dismissal.
    private func displayedTop(for raw: CGFloat) -> CGFloat {
        let tops = tops
        guard tops.hidden > tops.full else { return raw }
        return rubberband(
            value: raw,
            range: tops.full...tops.hidden,
            interval: SheetTuning.rubberBandInterval,
            c: SheetTuning.rubberBandConstant
        )
    }

    /// Velocity of the displayed top: the raw velocity scaled by the rubber band's slope.
    private func displayedVelocity(raw: CGFloat, velocity: CGFloat) -> CGFloat {
        let tops = tops
        guard tops.hidden > tops.full, raw < tops.full || raw > tops.hidden else { return velocity }
        let overshoot = raw > tops.hidden ? raw - tops.hidden : tops.full - raw
        let constant = SheetTuning.rubberBandConstant
        let factor = overshoot * constant / SheetTuning.rubberBandInterval + 1
        return velocity * constant / (factor * factor)
    }

    private func fadeSurface() {
        let target: CGFloat = detent == .full ? 1 : 0
        surfaceSpring.target = target
        if surfaceSpring.state != .running, surfaceSpring.value != target {
            surfaceSpring.start()
        }
    }

    private func playDetentFeedback() {
        feedbackTrigger &+= 1
        SheetTrace.log("haptic → \(detent)")
    }

    private var currentSpring: WaveSpring {
        if reduceMotion {
            return SheetSprings.reducedMotion
        }
        return bounces ? SheetSprings.bouncy : SheetSprings.settled
    }

    private var dismissalSpring: WaveSpring {
        reduceMotion ? SheetSprings.reducedMotion : SheetSprings.settled
    }

    /// DEBUG `-SheetInitialDetent collapsed|medium|full`, for scripted runs.
    private static var launchDetent: SheetDetent {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "SheetInitialDetent"),
           let detent = SheetDetent(rawValue: name) {
            return detent
        }
        #endif
        return .collapsed
    }
}
