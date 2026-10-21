//
//  UIMathUtilities.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

import CoreGraphics

nonisolated func rubberband(value: CGFloat, range: ClosedRange<CGFloat>, interval: CGFloat, c: CGFloat = 0.55) -> CGFloat {
    // * x = distance from the edge
    // * c = constant value, UIScrollView uses 0.55
    // * d = dimension, either width or height
    // b = (1.0 – (1.0 / ((x * c / d) + 1.0))) * d
    if range.contains(value) {
        return value
    }

    let d: CGFloat = interval

    if value > range.upperBound {
        let x = value - range.upperBound
        let b = (1.0 - (1.0 / ((x * c / d) + 1.0))) * d
        return range.upperBound + b
    } else {
        let x = range.lowerBound - value
        let b = (1.0 - (1.0 / ((x * c / d) + 1.0))) * d
        return range.lowerBound - b
    }
}

/**
 Returns a value bounded by the provided range.
 - parameter lower: The minimum allowable value (inclusive).
 - parameter upper: The maximum allowable value (inclusive).
 */
nonisolated func clip<T: FloatingPoint>(value: T, lower: T, upper: T) -> T {
    min(upper, max(value, lower))
}

/**
 Returns a value bounded by the range `[0, 1]`.
 */
nonisolated func clipUnit<T: FloatingPoint>(value: T) -> T {
    clip(value: value, lower: 0, upper: 1)
}
