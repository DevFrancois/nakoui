//
//  DisplayLinkProviding.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

import Foundation
import QuartzCore
import UIKit

typealias DisplayLinkCallback = (_ dt: TimeInterval) -> Void

final class CADisplayLinkProvider {

    let frameCallback: DisplayLinkCallback
    private var displayLinkProvider: CADisplayLink?

    init(frameCallback: @escaping DisplayLinkCallback) {
        self.frameCallback = frameCallback
    }

    func start() {
        guard displayLinkProvider == nil else {
            return
        }

        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))

        // Frame-rate clamp from Wave d95ce41: the minimum must never exceed the screen's maximum.
        let maxFPS = Float(maximumFramesPerSecond)
        let highFPSEnabled = maxFPS > 60
        let minFPS: Float = min(highFPSEnabled ? 80 : 60, maxFPS)
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: minFPS, maximum: maxFPS, preferred: maxFPS)
        displayLink.add(to: .main, forMode: .common)
        displayLinkProvider = displayLink
    }

    func stop() {
        displayLinkProvider?.invalidate()
        displayLinkProvider = nil
    }

    @objc
    func displayLinkFired(_ link: CADisplayLink) {
        let dt = (link.targetTimestamp - link.timestamp)
        self.frameCallback(dt)
    }

    /// The highest refresh rate of the app's screen. Avoids `UIScreen.main`, which is deprecated in iOS 26.
    private var maximumFramesPerSecond: Int {
        let screens = UIApplication.shared.connectedScenes.compactMap { scene in
            (scene as? UIWindowScene)?.screen
        }
        return screens.first?.maximumFramesPerSecond ?? 60
    }
}
