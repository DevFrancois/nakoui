//
//  Spring.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

import CoreGraphics
import Foundation

/**
 `WaveSpring` determines the timing curve and settling duration of an animation.

 Springs are created by providing a `dampingRatio` and a `response` value. See the initializer ``init(dampingRatio:response:mass:)`` for usage information.
 */
nonisolated final class WaveSpring: Equatable, Sendable {

    // MARK: - Spring Properties

    /**
     The amount of oscillation the spring will exhibit (i.e. "springiness").
     */
    let dampingRatio: CGFloat

    /**
     Represents the frequency response of the spring. This value affects how
     quickly the spring animation reaches its target value.
     */
    let response: CGFloat

    /**
     The spring constant `k`. This value is derived from `response`.
     */
    let stiffness: CGFloat

    /**
     The mass "attached" to the spring. The default value of `1.0` rarely needs to be modified.
     */
    let mass: CGFloat

    /**
     The viscous damping coefficient `c`. This value is derived.
     */
    let dampingCoefficient: CGFloat

    /**
     The time the spring will take to settle or "complete". This value is derived.
     */
    let settlingDuration: TimeInterval

    private static let DefaultSettlingPercentage = 0.0001

    // MARK: - Spring Initialization

    /**
     Creates a spring with the given damping ratio and frequency response.

     - parameter dampingRatio: The amount of oscillation the spring will exhibit (i.e. "springiness").
     A value of `1.0` (critically damped) will cause the spring to smoothly reach its target value without any oscillation.
     Values closer to `0.0` (underdamped) will increase oscillation (and overshoot the target) before settling.

     - parameter response: Represents the frequency response of the spring. This value affects how
     quickly the spring animation reaches its target value. The frequency response is the duration of one period
     in the spring's undamped system, measured in seconds.
     Values closer to `0` create a very fast animation, while values closer to `1.0` create a relatively slower animation.

     - parameter mass: The mass "attached" to the spring. The default value of `1.0` rarely needs to be modified.
     */
    init(dampingRatio: CGFloat, response: CGFloat, mass: CGFloat = 1.0) {
        precondition(dampingRatio >= 0)
        precondition(response >= 0)

        self.dampingRatio = dampingRatio
        self.response = response

        self.mass = mass
        self.stiffness = WaveSpring.stiffness(response: response, mass: mass)

        let unbandedDampingCoefficient = WaveSpring.dampingCoefficient(dampingRatio: dampingRatio, response: response, mass: mass)
        self.dampingCoefficient = rubberband(value: unbandedDampingCoefficient, range: 0...60, interval: 15)

        self.settlingDuration = WaveSpring.settlingTime(dampingRatio: dampingRatio, stiffness: stiffness, mass: mass)
    }

    // MARK: - Equatable

    static func == (lhs: WaveSpring, rhs: WaveSpring) -> Bool {
        lhs.dampingRatio == rhs.dampingRatio && lhs.response == rhs.response && lhs.mass == rhs.mass
    }

    static func stiffness(response: CGFloat, mass: CGFloat) -> CGFloat {
        pow(2.0 * .pi / response, 2.0) * mass
    }

    static func dampingCoefficient(dampingRatio: CGFloat, response: CGFloat, mass: CGFloat) -> CGFloat {
        4.0 * .pi * dampingRatio * mass / response
    }

    static let logOfSettlingPercentage = log(WaveSpring.DefaultSettlingPercentage)

    static func settlingTime(dampingRatio: CGFloat, stiffness: CGFloat, mass: CGFloat) -> CGFloat {
        if stiffness == .infinity {
            // A non-animated mode (i.e. a `response` of 0) results in a stiffness of infinity, and a settling time of 0.
            // We need the settling time to be non-zero such that the display link stays alive.
            return 1.0
        }

        if dampingRatio >= 1.0 {
            let criticallyDampedSettlingTime = settlingTime(dampingRatio: 1.0 - .ulpOfOne, stiffness: stiffness, mass: mass)
            return criticallyDampedSettlingTime * 1.25
        }

        let undampedNaturalFrequency = WaveSpring.undampedNaturalFrequency(stiffness: stiffness, mass: mass) // ωn
        return (-1 * (logOfSettlingPercentage / (dampingRatio * undampedNaturalFrequency)))
    }

    static func undampedNaturalFrequency(stiffness: CGFloat, mass: CGFloat) -> CGFloat {
        // ωn
        sqrt(stiffness / mass)
    }

}
