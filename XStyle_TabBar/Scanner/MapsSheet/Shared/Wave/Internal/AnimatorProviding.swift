//
//  AnimationProviding.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

import Foundation

protocol AnimatorProviding: AnyObject {
    var id: UUID { get }

    var state: AnimatorState { get }

    func updateAnimation(dt: TimeInterval)

    func reset()
}
