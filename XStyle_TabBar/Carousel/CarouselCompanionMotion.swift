import CoreGraphics
import Foundation

/// Independent companion momentum, driven by the exact same frame time as the cards.
struct CarouselCompanionMotion {
    private(set) var x: CarouselWaveValue
    private(set) var y: CarouselWaveValue
    private(set) var presence = CarouselWaveValue(value: 0)
    private(set) var scale = CarouselWaveValue(value: 1)
    private(set) var rotation = CarouselWaveValue(value: 0)
    private(set) var isInteracting = false
    private(set) var anchor: CGPoint
    private(set) var visible = false
    private var manipulation = CarouselManipulation()
    private var interactionBounds: CGRect?

    init(anchor: CGPoint) {
        self.anchor = anchor
        x = CarouselWaveValue(value: Double(anchor.x))
        y = CarouselWaveValue(value: Double(anchor.y))
    }

    private var scaleTarget: Double { manipulation.scale }
    private var rotationTarget: Double { manipulation.rotation }

    var position: CGPoint { CGPoint(x: x.value, y: y.value) }
    var renderedOpacity: CGFloat { CGFloat(min(1, max(0, presence.value))) }
    var renderedScale: CGFloat { CGFloat(max(0.1, scale.value * (0.3 + presence.value * 0.7))) }
    var renderedRise: CGFloat { CGFloat((1 - presence.value) * 14) }
    var gestureTargetCenter: CGPoint { CGPoint(x: target.x, y: target.y + renderedRise) }
    var needsAnimation: Bool {
        isInteracting || !x.isSettled(at: target.x) || !y.isSettled(at: target.y) ||
        !presence.isSettled(at: visible ? 1 : 0, distance: 0.001, speed: 0.01) ||
        !scale.isSettled(at: scaleTarget, distance: 0.001, speed: 0.005) ||
        !rotation.isSettled(at: rotationTarget, distance: 0.001, speed: 0.01)
    }
    var isHiddenAndSettled: Bool { !visible && !isInteracting && !needsAnimation }
    private var target: CGPoint {
        let offset = manipulation.offset
        let point = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
        guard isInteracting, let bounds = interactionBounds else { return point }
        return CGPoint(
            x: CarouselWave.rubberband(point.x, range: Double(bounds.minX)...Double(bounds.maxX), interval: 48),
            y: CarouselWave.rubberband(point.y, range: Double(bounds.minY)...Double(bounds.maxY), interval: 48))
    }

    mutating func constrainInteraction(to bounds: CGRect) { interactionBounds = bounds }

    mutating func retarget(anchor: CGPoint, visible: Bool) {
        if isInteracting {
            // Card simulation may move while its companion is held. Keep the user's
            // screen-space grip and only update the destination used on release.
            manipulation.offset.x += self.anchor.x - anchor.x
            manipulation.offset.y += self.anchor.y - anchor.y
        }
        self.anchor = anchor
        self.visible = visible
    }

    mutating func beginInteraction(at time: Double) {
        isInteracting = true
        // The first sample is the elastic target, which needs the offset in place.
        manipulation.offset = CGPoint(x: x.value - anchor.x, y: y.value - anchor.y)
        manipulation.begin(offset: manipulation.offset, scale: scale.value, rotation: rotation.value,
                           position: target, at: time)
    }

    /// `pivot` is the fingers' previous centroid: scaling and rotating keep the grip under
    /// them, as on a pinched card. Without it, `translation` moves the bubble as given.
    mutating func manipulate(translation: CGPoint, scaleFactor: Double, rotationDelta: Double,
                             pivot: CGPoint? = nil, at time: Double) {
        guard isInteracting else { return }
        if let pivot {
            manipulation.apply(translation: translation, scaleFactor: scaleFactor, rotationDelta: rotationDelta,
                               pivot: pivot, center: gestureTargetCenter)
        } else {
            manipulation.apply(translation: translation, scaleFactor: scaleFactor, rotationDelta: rotationDelta)
        }
        manipulation.record(position: target, at: time)
    }

    mutating func endInteraction(cancelled: Bool = false) {
        guard isInteracting else { return }
        isInteracting = false
        if !cancelled {
            let velocity = manipulation.releaseVelocity(positionCap: 2_000, scaleCap: 3, rotationCap: 12)
            x.velocity = Double(velocity.position.x)
            y.velocity = Double(velocity.position.y)
            scale.velocity = velocity.scale
            rotation.velocity = velocity.rotation
        }
        manipulation.rest(rotation: CarouselManipulation.upright(rotation.value))
    }

    mutating func reset() {
        isInteracting = false
        manipulation.rest(rotation: CarouselManipulation.upright(rotation.value))
    }

    mutating func nudge(horizontal: Double) {
        x.velocity += horizontal
    }

    mutating func advance(by seconds: Double, configuration: CarouselCompanionConfiguration,
                          cardIsDragging: Bool, reduceMotion: Bool = false) {
        let point = target
        guard configuration.motionEnabled && !reduceMotion else {
            x.snap(to: point.x)
            y.snap(to: point.y)
            presence.snap(to: visible ? 1 : 0)
            scale.snap(to: scaleTarget)
            rotation.snap(to: rotationTarget)
            return
        }
        let interactive = isInteracting || cardIsDragging
        let follow = CarouselWaveSpring(response: interactive ? 0.26 : 0.8,
            damping: interactive ? 0.8 : configuration.damping, mass: configuration.mass)
        let pop = CarouselWaveSpring(response: 0.35, damping: 0.55, mass: configuration.mass)
        x.advance(by: seconds, target: point.x, spring: follow)
        y.advance(by: seconds, target: point.y, spring: follow)
        // A held bubble keeps its presentation scale/rise so the contact point stays put.
        if isInteracting { presence.velocity = 0 }
        else { presence.advance(by: seconds, target: visible ? 1 : 0, spring: pop) }
        scale.advance(by: seconds, target: scaleTarget, spring: follow)
        rotation.advance(by: seconds, target: rotationTarget, spring: follow)
        if x.isSettled(at: point.x) { x.snap(to: point.x) }
        if y.isSettled(at: point.y) { y.snap(to: point.y) }
        if presence.isSettled(at: visible ? 1 : 0, distance: 0.001, speed: 0.01) {
            presence.snap(to: visible ? 1 : 0)
        }
        if scale.isSettled(at: scaleTarget, distance: 0.001, speed: 0.005) { scale.snap(to: scaleTarget) }
        if rotation.isSettled(at: rotationTarget, distance: 0.001, speed: 0.01) { rotation.snap(to: rotationTarget) }
    }
}
