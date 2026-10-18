import CoreGraphics
import Foundation

/// A short movement history in points and seconds. The window is interpolated at
/// its boundary so release speed does not depend on touch delivery frequency.
struct CarouselVelocityEstimator {
    private(set) var samples: [(point: CGPoint, time: Double)] = []

    mutating func add(_ point: CGPoint, at time: Double) {
        guard time.isFinite, point.x.isFinite, point.y.isFinite else { return }
        if let last = samples.last {
            guard time >= last.time else { return }
            if time == last.time {
                samples[samples.count - 1] = (point, time)
                return
            }
        }
        samples.append((point, time))
        while samples.count > 2 && samples[1].time <= time - 0.1 {
            samples.removeFirst()
        }
    }

    func velocity(at time: Double, cap: Double = 4_000) -> CGPoint {
        let x = CarouselInput.rate(samples.map { ($0.time, Double($0.point.x)) }, at: time)
        let y = CarouselInput.rate(samples.map { ($0.time, Double($0.point.y)) }, at: time)
        return CarouselInput.capped(CGPoint(x: x, y: y), magnitude: cap)
    }
}

enum CarouselGestureAxis: Equatable {
    case horizontal
    case vertical
}

enum CarouselGestureDecision {
    static func axis(for displacement: CGPoint) -> CarouselGestureAxis? {
        guard hypot(displacement.x, displacement.y) >= 8 else { return nil }
        return abs(displacement.x) > abs(displacement.y) ? .horizontal : .vertical
    }

    static func shouldDismiss(displacement: CGPoint, velocity: CGPoint, projection: Double) -> Bool {
        let x = Double(displacement.x) + Double(velocity.x) * projection
        let y = Double(displacement.y) + Double(velocity.y) * projection
        return max(abs(x), abs(y)) > 110
    }

    /// Progress follows the finger after resistance. A reversal through zero cancels.
    static func horizontalDirection(progress: Double, velocity: Double, pageWidth: Double,
                                    projection: Double) -> Int? {
        guard pageWidth > 0 else { return nil }
        let projected = progress + velocity * projection / pageWidth
        guard abs(projected) >= 0.35,
              progress == 0 || (projected > 0) == (progress > 0) else { return nil }
        return projected > 0 ? 1 : -1
    }

    static func resistedProgress(_ progress: Double) -> Double {
        let magnitude = abs(progress)
        guard magnitude > 1 else { return progress }
        let excess = magnitude - 1
        return (progress < 0 ? -1 : 1) * (1 + excess / (1 + 3 * excess))
    }

    static func isQuickTap(distance: Double, duration: Double) -> Bool {
        distance < 6 && duration >= 0 && duration < 0.2
    }
}

enum CarouselInput {
    /// One smooth multiplier keeps translation and rotation's inherited momentum together.
    /// Near zero this preserves the measured velocity; fast flicks approach a soft ceiling.
    static func swipeMomentumScale(speed: Double, limit: Double) -> Double {
        guard speed.isFinite, limit.isFinite, limit > 0 else { return 0 }
        let ratio = abs(speed) / limit
        return ratio > 0.000_001 ? tanh(ratio) / ratio : 1
    }

    static func capped(_ velocity: CGPoint, magnitude: Double) -> CGPoint {
        let speed = hypot(Double(velocity.x), Double(velocity.y))
        guard speed > magnitude, speed > 0 else { return velocity }
        return CGPoint(x: Double(velocity.x) * magnitude / speed,
                       y: Double(velocity.y) * magnitude / speed)
    }

    static func rate(_ samples: [(time: Double, value: Double)], at time: Double) -> Double {
        guard time.isFinite, let first = samples.first, let last = samples.last,
              samples.count > 1 else { return 0 }
        let cutoff = max(first.time, time - 0.1)
        guard cutoff < time, cutoff < last.time else { return 0 }
        var origin = first.value
        for index in 1..<samples.count {
            let left = samples[index - 1], right = samples[index]
            if right.time >= cutoff {
                let fraction = right.time > left.time ?
                    min(1, max(0, (cutoff - left.time) / (right.time - left.time))) : 1
                origin = left.value + (right.value - left.value) * fraction
                break
            }
        }
        return (last.value - origin) / (time - cutoff)
    }

    static func lever(at point: CGPoint, pose: CarouselPose, padding: Double = 0, limit: Double = 1) -> CGPoint {
        guard pose.height > 0 else { return .zero }
        let dx = Double(point.x) - pose.x, dy = Double(point.y) - pose.y
        let outer = pose.outerSize(padding: padding)
        let x = (dx * cos(pose.angle) + dy * sin(pose.angle)) / (Double(outer.width) / 2)
        let y = (-dx * sin(pose.angle) + dy * cos(pose.angle)) / (Double(outer.height) / 2)
        return CGPoint(x: min(limit, max(-limit, x)), y: min(limit, max(-limit, y)))
    }

    static func anchorOffset(lever: CGPoint, pose: CarouselPose, padding: Double = 0) -> CGPoint {
        let outer = pose.outerSize(padding: padding)
        let x = Double(lever.x) * Double(outer.width) / 2
        let y = Double(lever.y) * Double(outer.height) / 2
        return CGPoint(x: x * cos(pose.angle) - y * sin(pose.angle),
                       y: x * sin(pose.angle) + y * cos(pose.angle))
    }

    static func centerVelocity(anchorVelocity: CGPoint, lever: CGPoint, pose: CarouselPose,
                               heightVelocity: Double, angularVelocity: Double, padding: Double = 0) -> CGPoint {
        let offset = anchorOffset(lever: lever, pose: pose, padding: padding)
        // Padding remains fixed in screen points as the image grows. Only the
        // image dimensions contribute to the grip's size derivative.
        let localX = Double(lever.x) * heightVelocity * 0.4
        let localY = Double(lever.y) * heightVelocity * 0.5
        let sizeX = localX * cos(pose.angle) - localY * sin(pose.angle)
        let sizeY = localX * sin(pose.angle) + localY * cos(pose.angle)
        return capped(CGPoint(x: Double(anchorVelocity.x) - sizeX + angularVelocity * Double(offset.y),
                              y: Double(anchorVelocity.y) - sizeY - angularVelocity * Double(offset.x)),
                      magnitude: 4_000)
    }
}
