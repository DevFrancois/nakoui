import CoreGraphics

nonisolated extension CGPoint {
    func lerp(to other: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    /// Unit vector from `self` toward `other`, or zero when they coincide.
    func direction(to other: CGPoint) -> CGPoint {
        let length = distance(to: other)
        guard length > 0 else { return .zero }
        return CGPoint(x: (other.x - x) / length, y: (other.y - y) / length)
    }
}
