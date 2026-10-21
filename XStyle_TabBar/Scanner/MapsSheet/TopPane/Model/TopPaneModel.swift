//
//  TopPaneModel.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics
import Foundation
import Observation
import QuartzCore

/// The pane's own motion: the velocity-driven stretch behind its horizontal squash, and the footer under it easing to
/// its measured height. Its position comes straight from `SheetController.sheetTop`, so it never trails the sheet.
@Observable
final class TopPaneModel {
    private(set) var stretch: CGFloat = 0
    /// The footer height the pane makes room for: the first measurement at once, later ones eased, so the pane slides
    /// as the footer grows or shrinks.
    private(set) var footerHeight: CGFloat = 0

    @ObservationIgnored var reduceMotion = false {
        didSet {
            if reduceMotion, reduceMotion != oldValue {
                stop()
            }
        }
    }

    /// Debug setting: off, the pane ignores the sheet's speed and keeps its shape.
    @ObservationIgnored var stretchEnabled = true {
        didSet {
            if !stretchEnabled, stretchEnabled != oldValue {
                stop()
            }
        }
    }

    @ObservationIgnored private var lastVelocityTime: CFTimeInterval = 0
    @ObservationIgnored private var staleCheckTask: Task<Void, Never>?
    @ObservationIgnored private var isSmoothed = false
    /// The speed the stretch follows: filtered when smoothed, raw otherwise.
    @ObservationIgnored private var followedVelocity: CGFloat = 0

    private let stretchAnimator = SpringAnimator<CGFloat>(
        spring: PaneSprings.stretch(isSmoothed: false),
        value: 0,
        target: 0
    )
    private let footerAnimator = SpringAnimator<CGFloat>(spring: PaneSprings.footer, value: 0, target: 0)
    @ObservationIgnored private var hasMeasuredFooter = false

    init() {
        stretchAnimator.valueChanged = { [weak self] value in
            // Bound the visible stretch without discarding the spring's internal momentum.
            self?.stretch = clip(value: value, lower: -1, upper: 1)
        }
        footerAnimator.valueChanged = { [weak self] value in
            self?.footerHeight = max(value, 0)
        }
    }

    /// Call with the footer's measured height. The first lands at once, so the pane first appears in place, as do all
    /// of them with Reduce Motion; later ones ease there, retargeting a move under way.
    func setMeasuredFooter(_ height: CGFloat) {
        guard hasMeasuredFooter, !reduceMotion else {
            hasMeasuredFooter = true
            settleFooter(at: height)
            return
        }
        guard footerAnimator.target != height else { return }
        footerAnimator.target = height
        if footerAnimator.state != .running {
            footerAnimator.start()
        }
    }

    private func settleFooter(at height: CGFloat) {
        footerAnimator.stop()
        footerAnimator.value = height
        footerAnimator.target = height
        footerAnimator.velocity = 0
        footerHeight = height
    }

    /// Change the motion character while preserving the current presentation value and velocity.
    func configure(isSmoothed: Bool) {
        guard isSmoothed != self.isSmoothed else { return }
        self.isSmoothed = isSmoothed
        stretchAnimator.spring = PaneSprings.stretch(isSmoothed: isSmoothed)
        if stretchAnimator.state == .running, let value = stretchAnimator.value {
            // Refresh the settling clock for the new spring without resetting its momentum.
            stretchAnimator.restart(value: value, velocity: stretchAnimator.velocity)
        }
    }

    /// Displayed sheet velocity in pt/s, positive downward; 0 once the sheet stops.
    func sheetVelocityDidChange(_ velocity: CGFloat) {
        guard !reduceMotion, stretchEnabled else { return }
        /// A touch move without movement reports 0 mid-drag; smoothed, real stops are left to the stale check.
        if isSmoothed, velocity == 0 { return }
        let now = CACurrentMediaTime()
        if isSmoothed {
            /// UIKit's touch speed jumps between moves: follow a moving average with a fixed time constant.
            let elapsed = lastVelocityTime > 0 ? now - lastVelocityTime : .infinity
            let weight = CGFloat(1 - exp(-elapsed / PaneTuning.velocitySmoothing))
            followedVelocity += (velocity - followedVelocity) * weight
        } else {
            followedVelocity = velocity
        }
        lastVelocityTime = now
        retarget(velocity: followedVelocity)
    }

    private func retarget(velocity: CGFloat) {
        let target = clip(value: velocity / PaneTuning.stretchReferenceVelocity, lower: -1, upper: 1)
        // Like Wave's interactive examples, retarget the same animator rather than restarting each update.
        if stretchAnimator.target != target {
            stretchAnimator.target = target
        }
        if stretchAnimator.state != .running, stretchAnimator.value != target {
            stretchAnimator.start()
        }
        if target != 0 {
            scheduleStaleCheck()
        } else {
            staleCheckTask?.cancel()
            staleCheckTask = nil
        }
    }

    /// Immediately neutralize motion when the pane disappears or Reduce Motion is enabled. The footer settles at the
    /// height it was easing to: the pane must reappear where it was going.
    func stop() {
        staleCheckTask?.cancel()
        staleCheckTask = nil
        lastVelocityTime = 0
        followedVelocity = 0
        // Keep the animator ended so the display-link controller removes its registration.
        stretchAnimator.stop()
        stretchAnimator.value = 0
        stretchAnimator.target = 0
        stretchAnimator.velocity = 0
        stretch = 0
        if let target = footerAnimator.target {
            settleFooter(at: target)
        }
    }

    /// A finger can stop without lifting and nothing reports it, so drop the stretch once the velocity goes stale.
    private func scheduleStaleCheck() {
        guard staleCheckTask == nil else { return }
        staleCheckTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(PaneTuning.freshInterval))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            staleCheckTask = nil
            if CACurrentMediaTime() - lastVelocityTime >= PaneTuning.freshInterval {
                followedVelocity = 0
                retarget(velocity: 0)
            } else {
                scheduleStaleCheck()
            }
        }
    }
}
