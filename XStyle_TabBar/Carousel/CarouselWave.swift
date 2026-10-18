// Spring equations adapted from Wave, copyright (c) 2022 Janum Trivedi.
// Distributed under the MIT license; see docs/licenses/Wave-LICENSE.md.
import CoreGraphics
import Foundation

/// Wave's mass/spring/damper model, stepped by the carousel's existing clock.
struct CarouselWaveSpring {
    let mass: Double
    let stiffness: Double
    let dampingCoefficient: Double

    init(response: Double, damping: Double, mass: Double = 1) {
        // Keep stiffness fixed as mass changes so a heavier companion really lags more.
        self.mass = mass.isFinite ? min(5, max(0.1, mass)) : 1
        let period = response.isFinite ? max(0.05, response) : 0.8
        let ratio = damping.isFinite ? min(2, max(0.05, damping)) : 0.68
        stiffness = pow(2 * .pi / period, 2)
        dampingCoefficient = 2 * ratio * sqrt(stiffness * self.mass)
    }

    var response: Double { 2 * .pi / sqrt(stiffness / mass) }

    /// Wave's semi-implicit Euler update, with no wall clock or display-link ownership.
    func step(value: Double, target: Double, velocity: Double, dt: Double) -> (Double, Double) {
        let springForce = -stiffness * (value - target)
        let dampingForce = dampingCoefficient * velocity
        let acceleration = (springForce - dampingForce) / mass
        let newVelocity = velocity + acceleration * dt
        return (value + newVelocity * dt, newVelocity)
    }
}

struct CarouselWaveValue {
    var value: Double
    var velocity: Double = 0

    mutating func advance(by seconds: Double, target: Double, spring: CarouselWaveSpring) {
        guard seconds.isFinite, seconds > 0, target.isFinite else { return }
        // Substeps keep the copied integrator stable across display-rate changes.
        let duration = min(seconds, 0.1)
        let steps = max(1, Int(ceil(duration * 240 - 0.000_001)))
        let dt = duration / Double(steps)
        for _ in 0..<steps {
            (value, velocity) = spring.step(value: value, target: target, velocity: velocity, dt: dt)
        }
    }

    func isSettled(at target: Double, distance: Double = 0.25, speed: Double = 2) -> Bool {
        abs(value - target) <= distance && abs(velocity) <= speed
    }

    mutating func snap(to target: Double) {
        value = target
        velocity = 0
    }
}

enum CarouselWave {
    /// Wave's elastic limiting function; never hard-clips an active gesture.
    static func rubberband(_ value: Double, range: ClosedRange<Double>, interval: Double) -> Double {
        guard !range.contains(value) else { return value }
        let extent = max(0.001, interval)
        let distance = value > range.upperBound ? value - range.upperBound : range.lowerBound - value
        let offset = (1 - 1 / (distance * 0.55 / extent + 1)) * extent
        return value > range.upperBound ? range.upperBound + offset : range.lowerBound - offset
    }
}

/// Finger geometry shared by companions and selected cards: the change between two
/// samples of the same fingers, and the translation that keeps a grip under them.
enum CarouselTouchGeometry {
    static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(max(1, points.count))
        return points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / count, y: $0.y + $1.y / count) }
    }

    /// Matching touch membership is required; rebaseline when fingers enter or leave.
    static func delta(from old: [CGPoint], to new: [CGPoint]) -> (translation: CGPoint, scale: Double, rotation: Double) {
        guard !old.isEmpty, old.count == new.count else { return (.zero, 1, 0) }
        let oldCenter = centroid(old), newCenter = centroid(new)
        let translation = CGPoint(x: newCenter.x - oldCenter.x, y: newCenter.y - oldCenter.y)
        guard old.count > 1 else { return (translation, 1, 0) }
        let a = CGPoint(x: old[1].x - old[0].x, y: old[1].y - old[0].y)
        let b = CGPoint(x: new[1].x - new[0].x, y: new[1].y - new[0].y)
        let oldLength = hypot(a.x, a.y), newLength = hypot(b.x, b.y)
        guard oldLength > 4, newLength > 4 else { return (translation, 1, 0) }
        let angle = atan2(b.y, b.x) - atan2(a.y, a.x)
        return (translation, Double(newLength / oldLength), Double(atan2(sin(angle), cos(angle))))
    }

    /// Scale and rotate around the fingers, preserving the user's off-centre grip.
    static func anchoredTranslation(_ translation: CGPoint, scale: Double, rotation: Double,
                                    center: CGPoint, pivot: CGPoint) -> CGPoint {
        let x = Double(center.x - pivot.x), y = Double(center.y - pivot.y)
        let transformedX = scale * (x * cos(rotation) - y * sin(rotation))
        let transformedY = scale * (x * sin(rotation) + y * cos(rotation))
        return CGPoint(x: Double(translation.x) + transformedX - x, y: Double(translation.y) + transformedY - y)
    }
}

/// A drag/pinch/rotation's targets and release speeds, shared by companions and
/// selected cards. Scale and rotation resist softly past their limits.
struct CarouselManipulation {
    static let scaleLimits: ClosedRange<Double> = 0.75...1.25
    /// How quickly resistance builds past a scale limit, in natural-log units of scale.
    static let scaleSoftness = 0.08
    /// Rotation from upright either way before resistance, in radians (25°).
    static let rotationLimit = 25 * Double.pi / 180
    /// How quickly resistance builds past the rotation limit, in radians.
    static let rotationSoftness = 0.05

    /// Position relative to the owner's resting point.
    var offset: CGPoint = .zero
    private(set) var scale: Double = 1
    private(set) var rotation: Double = 0
    private(set) var lastTime: Double = 0
    /// The upright angle rotation is limited around.
    private(set) var restRotation: Double = 0
    private var rawScale: Double = 1
    private var rawRotation: Double = 0
    private var positionSamples = CarouselVelocityEstimator()
    private var scaleSamples: [(Double, Double)] = []
    private var rotationSamples: [(Double, Double)] = []

    /// Follows `value` inside `limits` and ever more slowly past them, with no ceiling
    /// and no kink at a limit: past it, the excess grows as k·ln(1 + excess/k).
    static func soften(_ value: Double, limits: ClosedRange<Double>, softness: Double) -> Double {
        let k = max(0.000_001, softness)
        if value > limits.upperBound { return limits.upperBound + k * log(1 + (value - limits.upperBound) / k) }
        if value < limits.lowerBound { return limits.lowerBound - k * log(1 + (limits.lowerBound - value) / k) }
        return value
    }

    /// The input `soften` maps to `value`.
    static func unsoften(_ value: Double, limits: ClosedRange<Double>, softness: Double) -> Double {
        let k = max(0.000_001, softness)
        if value > limits.upperBound { return limits.upperBound + k * (exp((value - limits.upperBound) / k) - 1) }
        if value < limits.lowerBound { return limits.lowerBound - k * (exp((limits.lowerBound - value) / k) - 1) }
        return value
    }

    /// Zoom follows the fingers inside the limits and ever more slowly past them (in log scale).
    static func softLimitedScale(_ raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return 1 }
        return exp(soften(log(raw), limits: log(scaleLimits.lowerBound)...log(scaleLimits.upperBound),
                          softness: scaleSoftness))
    }

    /// The finger scale `softLimitedScale` maps to `scale`.
    static func rawScale(forSoftLimited scale: Double) -> Double {
        guard scale.isFinite, scale > 0 else { return 1 }
        return exp(unsoften(log(scale), limits: log(scaleLimits.lowerBound)...log(scaleLimits.upperBound),
                            softness: scaleSoftness))
    }

    /// Rotation follows the fingers within 25° of `rest` and ever more slowly past it.
    static func softLimitedRotation(_ raw: Double, around rest: Double) -> Double {
        guard raw.isFinite else { return rest }
        return rest + soften(raw - rest, limits: -rotationLimit...rotationLimit, softness: rotationSoftness)
    }

    static func rawRotation(forSoftLimited rotation: Double, around rest: Double) -> Double {
        guard rotation.isFinite else { return rest }
        return rest + unsoften(rotation - rest, limits: -rotationLimit...rotationLimit, softness: rotationSoftness)
    }

    /// Starts from the owner as it is now, including a scale or angle already past a limit.
    mutating func begin(offset: CGPoint, scale: Double, rotation: Double, position: CGPoint, at time: Double) {
        self.offset = offset
        self.scale = scale
        self.rotation = rotation
        restRotation = Self.upright(rotation)
        rawScale = Self.rawScale(forSoftLimited: scale)
        rawRotation = Self.rawRotation(forSoftLimited: rotation, around: restRotation)
        positionSamples = CarouselVelocityEstimator()
        scaleSamples = []
        rotationSamples = []
        record(position: position, at: time)
    }

    /// Returns the scale factor and rotation actually applied after the soft limits.
    @discardableResult
    mutating func apply(translation: CGPoint, scaleFactor: Double, rotationDelta: Double)
        -> (scale: Double, rotation: Double) {
        if translation.x.isFinite, translation.y.isFinite {
            offset.x += translation.x
            offset.y += translation.y
        }
        let previousScale = scale, previousRotation = rotation
        if scaleFactor.isFinite, scaleFactor > 0 {
            rawScale *= scaleFactor
            scale = Self.softLimitedScale(rawScale)
        }
        if rotationDelta.isFinite {
            rawRotation += rotationDelta
            rotation = Self.softLimitedRotation(rawRotation, around: restRotation)
        }
        return (previousScale > 0 ? scale / previousScale : 1, rotation - previousRotation)
    }

    /// One step of the fingers: scale and rotate around their previous centroid `pivot`,
    /// then follow its movement. `center` is the owner's target centre before the step.
    /// The grip uses the scale and rotation the soft limits allowed, so it stays put.
    mutating func apply(translation: CGPoint, scaleFactor: Double, rotationDelta: Double,
                        pivot: CGPoint, center: CGPoint) {
        let applied = apply(translation: .zero, scaleFactor: scaleFactor, rotationDelta: rotationDelta)
        apply(translation: CarouselTouchGeometry.anchoredTranslation(translation, scale: applied.scale,
                  rotation: applied.rotation, center: center, pivot: pivot),
              scaleFactor: 1, rotationDelta: 0)
    }

    /// Samples the owner's target position with the current scale and rotation.
    mutating func record(position: CGPoint, at time: Double) {
        positionSamples.add(position, at: time)
        scaleSamples.append((time, scale))
        rotationSamples.append((time, rotation))
        scaleSamples.removeAll { $0.0 < time - 0.12 }
        rotationSamples.removeAll { $0.0 < time - 0.12 }
        lastTime = time
    }

    func releaseVelocity(positionCap: Double, scaleCap: Double, rotationCap: Double)
        -> (position: CGPoint, scale: Double, rotation: Double) {
        let position = positionSamples.velocity(at: lastTime, cap: positionCap)
        let scale = min(scaleCap, max(-scaleCap, CarouselInput.rate(scaleSamples, at: lastTime)))
        let rotation = min(rotationCap, max(-rotationCap, CarouselInput.rate(rotationSamples, at: lastTime)))
        return (position, scale, rotation)
    }

    /// Back to the resting offset and scale, keeping the given rotation target.
    mutating func rest(rotation: Double) {
        offset = .zero
        rawScale = 1
        scale = 1
        restRotation = rotation
        rawRotation = rotation
        self.rotation = rotation
    }

    /// Retains winding; a nearly complete rotation takes the short route upright.
    static func upright(_ angle: Double) -> Double {
        (angle / (2 * .pi)).rounded() * 2 * .pi
    }
}
