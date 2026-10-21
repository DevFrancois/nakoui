//
//  PaneDisappearModifier.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Transforms the complete, minimum-height card rather than sampling its colored rows away.
/// Sheet position owns the travel and visibility; a retained Wave spring adds secondary deformation.
struct PaneDisappearModifier: ViewModifier {
    var motion: PaneEffectMotion
    var effect: PaneEffect
    var size: CGSize
    /// A small destination inside the top safe area, relative to the card's origin.
    var destination: CGRect
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        let pose = PaneDisappearPose(
            motion: motion,
            effect: effect,
            size: size,
            destination: destination,
            reduceMotion: reduceMotion
        )

        content
            .clipShape(.rect(cornerRadius: pose.cornerRadius))
            .distortionEffect(
                ShaderLibrary.paneFunnel(.boundingRect, .float(pose.funnel)),
                maxSampleOffset: CGSize(width: size.width, height: 0),
                isEnabled: pose.funnel > 0
            )
            .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .top)
            .offset(y: pose.offsetY)
            .blur(radius: pose.blur)
            .opacity(pose.opacity)
            .allowsHitTesting(motion.progress < 0.05)
            .accessibilityHidden(motion.progress >= 0.5)
    }

    static func precompile() async {
        let shader = ShaderLibrary.paneFunnel(.boundingRect, .float(0))
        try? await shader.compile(as: .distortionEffect)
    }
}

/// Coordinates shape changes without adding another animation to sheet position.
nonisolated struct PaneEffectMotion {
    let progress: CGFloat
    /// Positive while collapsing, negative while opening, with Wave preserving momentum on reversal.
    let deformation: CGFloat

    init(progress: CGFloat, stretch: CGFloat, reduceMotion: Bool) {
        let p = min(max(progress, 0), 1)
        self.progress = p
        // Zero value and slope at each endpoint prevent lingering deformation at either detent.
        let envelope = p > 0 && p < 1 ? pow(sin(.pi * p), 2) : 0
        deformation = reduceMotion ? 0 : -min(max(stretch, -1), 1) * envelope
    }

    var appearanceProgress: CGFloat {
        min(max(progress + 0.08 * deformation, 0), 1)
    }

    static func ease(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

    static func ramp(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        ease(min(max((value - start) / (end - start), 0), 1))
    }
}

/// No implicit animation: the controller's display-link updates are already interpolated.
private struct PaneDisappearPose {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var offsetY: CGFloat = 0
    var blur: CGFloat = 0
    var opacity: Double = 1
    var cornerRadius: CGFloat = 0
    var funnel: CGFloat = 0

    init(motion: PaneEffectMotion, effect: PaneEffect, size: CGSize, destination: CGRect, reduceMotion: Bool) {
        let p = motion.progress
        let deformation = motion.deformation
        guard !reduceMotion else {
            opacity = Double(1 - PaneEffectMotion.ease(p))
            return
        }

        let widthProgress = PaneEffectMotion.ease(p)
        let baseWidth = 1 + (destination.width / max(size.width, 1) - 1) * widthProgress
        // The same spring survives quick reversals, so the token flexes without restarting.
        scaleX = min(baseWidth * (1 - 0.10 * deformation), 1)
        // Linear vertical travel keeps the bottom above the rising sheet at every frame.
        // Easing this axis would let the sheet cover the gradient before it can converge.
        scaleY = 1 + (destination.height / max(size.height, 1) - 1) * p
        offsetY = destination.minY * p
        cornerRadius = min(size.width, size.height) * 0.5 * PaneEffectMotion.ease(motion.appearanceProgress)
        opacity = Double(1 - PaneEffectMotion.ramp(p, from: 0.72, to: 1))
        blur = 1.2 * PaneEffectMotion.ramp(p, from: 0.65, to: 1)
        if effect == .funnel {
            // The shader's minimum row width is 0.4; keep the pinch within that sampling budget.
            funnel = min(max(0.48 * sin(.pi * p) + 0.14 * deformation, 0), 0.60)
        }
    }
}
