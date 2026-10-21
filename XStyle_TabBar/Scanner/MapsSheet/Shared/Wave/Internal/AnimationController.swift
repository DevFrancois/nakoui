//
//  AnimationController.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

import Foundation
import QuartzCore

final class AnimationController {

    static let shared = AnimationController()

    // The explicit type annotation is required: the closure references `displayLinkProvider` itself.
    private lazy var displayLinkProvider: CADisplayLinkProvider = CADisplayLinkProvider { [weak self] dt in
        guard let strongSelf = self else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for animation in strongSelf.animations.values {
            if animation.state == .ended {
                animation.reset()
                strongSelf.animations.removeValue(forKey: animation.id)
            } else {
                animation.updateAnimation(dt: dt)
            }
        }

        CATransaction.commit()

        if strongSelf.animations.isEmpty {
            strongSelf.displayLinkProvider.stop()
        }
    }

    private var animations: [UUID: AnimatorProviding] = [:]

    func runPropertyAnimation(_ animation: AnimatorProviding) {
        if animations.isEmpty {
            displayLinkProvider.start()
        }

        animations[animation.id] = animation

        animation.updateAnimation(dt: .zero)
    }

}
