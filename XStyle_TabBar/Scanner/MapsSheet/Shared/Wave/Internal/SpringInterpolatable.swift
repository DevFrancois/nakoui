//
//  SpringInterpolatable.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

import CoreGraphics
import Foundation

nonisolated protocol SpringInterpolatable: Equatable {
    associatedtype ValueType: SpringInterpolatable
    associatedtype VelocityType: VelocityProviding

    static func updateValue(spring: WaveSpring, value: ValueType, target: ValueType, velocity: VelocityType, dt: TimeInterval) -> (value: ValueType, velocity: VelocityType)
}

nonisolated protocol VelocityProviding {
    static var zero: Self { get }
}

nonisolated extension CGFloat: SpringInterpolatable, VelocityProviding {
    typealias ValueType = CGFloat
    typealias VelocityType = CGFloat

    static func updateValue(spring: WaveSpring, value: CGFloat, target: CGFloat, velocity: CGFloat, dt: TimeInterval) -> (value: CGFloat, velocity: CGFloat) {
        precondition(spring.response > 0, "Shouldn't be calculating spring physics with a frequency response of zero.")

        let displacement = value - target
        let springForce = (-spring.stiffness * displacement)
        let dampingForce = (spring.dampingCoefficient * velocity)
        let force = springForce - dampingForce
        let acceleration = force / spring.mass

        let newVelocity = (velocity + (acceleration * dt))
        let newValue = (value + (newVelocity * dt))

        return (value: newValue, velocity: newVelocity)
    }
}
