//
//  SpringAnimator.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

import Foundation
import QuartzCore

final class SpringAnimator<T: SpringInterpolatable>: AnimatorProviding {

    /**
     A unique identifier for the animation.
     */
    let id = UUID()

    /**
     The execution state of the animation (`inactive`, `running`, or `ended`).
     */
    private(set) var state: AnimatorState = .inactive {
        didSet {
            switch (oldValue, state) {
            case (.inactive, .running), (.ended, .running):
                // Fix vs upstream (which only handled `.inactive` → `.running`): an animator that is started again
                // after it ended, but before the animation controller reset it on the next frame, must restart its
                // settling clock too. Otherwise `runningTime` keeps counting from the previous run and the animation
                // snaps to its target on the first frame.
                self.startTime = CACurrentMediaTime()

            default:
                break
            }
        }
    }

    /**
     The spring model that determines the animation's motion.
     */
    var spring: WaveSpring

    /**
     The _current_ value of the animation. This value will change as the animation executes.

     `value` needs to be set to a non-nil value before the animation can start.
     */
    var value: T.ValueType?

    /**
     The current target value of the animation.

     You may modify this value while the animation is in-flight to "retarget" to a new target value.
     */
    var target: T.ValueType? {
        didSet {
            guard let oldValue = oldValue, let newValue = target else {
                return
            }

            if oldValue == newValue {
                return
            }

            if state == .running {
                self.startTime = CACurrentMediaTime()
            }
        }
    }

    /**
     The current velocity of the animation.

     If animating a view's `center` or `frame` with a gesture, you may want to set `velocity` to the gesture's final velocity on touch-up.
     */
    var velocity: T.VelocityType

    /**
     The callback block to call when the animation's `value` changes as it executes. Use the `currentValue` to drive your application's animations.
     */
    var valueChanged: ((_ currentValue: T.ValueType) -> Void)?

    private var startTime: TimeInterval?

    /**
     Creates a new animation with a given `WaveSpring`, and optionally, an initial and target value.
     While `value` and `target` are optional in the initializer, they must be set to non-nil values before the animation can start.

     - parameter spring: The spring model that determines the animation's motion.
     - parameter value: The initial, starting value of the animation.
     - parameter target: The target value of the animation.
     */
    init(spring: WaveSpring, value: T.ValueType? = nil, target: T.ValueType? = nil) {
        self.value = value
        self.target = target
        self.velocity = T.VelocityType.zero

        self.spring = spring
    }

    /**
     Starts the animation (if not already running).
     */
    func start() {
        precondition(value != nil, "Animation must have a non-nil `value` before starting.")
        precondition(target != nil, "Animation must have a non-nil `target` before starting.")

        AnimationController.shared.runPropertyAnimation(self)
    }

    /**
     Re-seeds the animation with a new `value` and `velocity`, then starts it with a fresh settling clock.

     Use this when the `target` does not change between runs (for example an offset spring that always settles
     back to `0`): retargeting only restarts the clock when the target actually changes, so `restart` is the way to
     replay the spring from a new position and velocity.

     - parameter value: The new starting value of the animation.
     - parameter velocity: The new starting velocity of the animation.
     */
    func restart(value: T.ValueType, velocity: T.VelocityType) {
        reset()
        self.value = value
        self.velocity = velocity
        start()
    }

    /**
     Stops the animation at the current value.

     The animation freezes at its current `value`; it does not snap to `target`.
     */
    func stop() {
        self.state = .ended
    }

    /**
     How long the animation will take to complete, based off its `spring` property.

     Note: This is useful for debugging purposes only. Do not use `settlingTime` to determine the animation's progress.
     */
    var settlingTime: TimeInterval {
        spring.settlingDuration
    }

    private var runningTime: TimeInterval? {
        if let startTime = startTime {
            return (CACurrentMediaTime() - startTime)
        } else {
            return nil
        }
    }

    func reset() {
        self.startTime = nil
        self.velocity = .zero
        self.state = .inactive
    }

    func updateAnimation(dt: TimeInterval) {
        guard let value = value, let target = target else {
            // Can't start an animation without a value and target
            self.state = .inactive
            return
        }

        self.state = .running

        guard let runningTime = runningTime else {
            fatalError("Found a nil `runningTime` even though the animation's state is \(state)")
        }

        let newValue: T.ValueType
        let newVelocity: T.VelocityType

        let isAnimated = spring.response > .zero

        if isAnimated {
            (newValue, newVelocity) = T.updateValue(spring: spring, value: value, target: target, velocity: velocity, dt: dt)
        } else {
            newValue = target
            newVelocity = T.VelocityType.zero
        }

        self.value = newValue
        self.velocity = newVelocity

        let animationFinished = (runningTime >= settlingTime) || !isAnimated

        if animationFinished {
            self.value = target
        }

        // Fix vs upstream: `valueChanged` may retarget or restart this animator, which restarts its settling clock.
        // Only end the run if the clock is unchanged, so a retarget or restart made on the final frame is kept.
        let startTimeBeforeCallback = startTime

        if let value = self.value {
            valueChanged?(value)
        }

        if animationFinished && startTime == startTimeBeforeCallback {
            self.state = .ended
        }
    }
}
