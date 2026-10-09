import SwiftUI

/// Four corners in reading order, clockwise on screen (y points down):
/// top-left, top-right, bottom-right, bottom-left. This order matches the
/// unit square (0,0) (1,0) (1,1) (0,1) used by `Homography.unitSquare(to:)`.
nonisolated struct Quad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    init(_ rect: CGRect) {
        self.init(
            topLeft: CGPoint(x: rect.minX, y: rect.minY),
            topRight: CGPoint(x: rect.maxX, y: rect.minY),
            bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
            bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        )
    }

    var corners: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var center: CGPoint {
        CGPoint(
            x: (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4,
            y: (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4
        )
    }

    /// Mean length of the top and bottom edges.
    var width: CGFloat {
        (topLeft.distance(to: topRight) + bottomLeft.distance(to: bottomRight)) / 2
    }

    /// Mean length of the left and right edges.
    var height: CGFloat {
        (topLeft.distance(to: bottomLeft) + topRight.distance(to: bottomRight)) / 2
    }

    /// Strictly convex and wound like a screen rect. Only such quads give a
    /// homography whose w stays positive over the whole source rect, so the
    /// warped layer never renders past the horizon line or mirrored.
    var isConvexAndUpright: Bool {
        let p = corners
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if cross <= 0 { return false }
        }
        return true
    }

    func lerp(to other: Quad, _ t: CGFloat) -> Quad {
        Quad(
            topLeft: topLeft.lerp(to: other.topLeft, t),
            topRight: topRight.lerp(to: other.topRight, t),
            bottomRight: bottomRight.lerp(to: other.bottomRight, t),
            bottomLeft: bottomLeft.lerp(to: other.bottomLeft, t)
        )
    }

    func map(_ transform: (CGPoint) -> CGPoint) -> Quad {
        Quad(
            topLeft: transform(topLeft),
            topRight: transform(topRight),
            bottomRight: transform(bottomRight),
            bottomLeft: transform(bottomLeft)
        )
    }

    /// Grows the quad outward along its own edges: `leading`/`trailing` along
    /// the top edge's direction, `top`/`bottom` along the left edge's.
    func expanded(leading: CGFloat, trailing: CGFloat, top: CGFloat, bottom: CGFloat) -> Quad {
        let across = topLeft.direction(to: topRight).lerp(to: bottomLeft.direction(to: bottomRight), 0.5)
        let down = topLeft.direction(to: bottomLeft).lerp(to: topRight.direction(to: bottomRight), 0.5)
        func shift(_ p: CGPoint, _ a: CGFloat, _ d: CGFloat) -> CGPoint {
            CGPoint(x: p.x + across.x * a + down.x * d, y: p.y + across.y * a + down.y * d)
        }
        return Quad(
            topLeft: shift(topLeft, -leading, -top),
            topRight: shift(topRight, trailing, -top),
            bottomRight: shift(bottomRight, trailing, bottom),
            bottomLeft: shift(bottomLeft, -leading, bottom)
        )
    }

    /// The smallest axis-aligned rect around the corners.
    var boundingBox: CGRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    /// Turned by `angle` radians around the centre.
    func rotated(by angle: CGFloat) -> Quad {
        let c = center, cosine = cos(angle), sine = sin(angle)
        return map { p in
            let dx = p.x - c.x, dy = p.y - c.y
            return CGPoint(x: c.x + dx * cosine - dy * sine, y: c.y + dx * sine + dy * cosine)
        }
    }

    /// On its way from here to `target` as `t` goes from 0 to 1, turning as it
    /// goes rather than moving each corner straight across. A code seen
    /// upside down then rights itself instead of collapsing through a point.
    func lifted(to target: CGRect, _ t: CGFloat) -> Quad {
        let angle = atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)
        return rotated(by: -angle * t).lerp(to: Quad(target), t)
    }

    /// The same corners, renamed in order so `topLeft` is the one nearest
    /// `other.topLeft`. For symmetric drawings such as brackets, so flying
    /// from `other` to here never crosses corners over.
    func cornersAligned(to other: Quad) -> Quad {
        let points = corners, targets = other.corners
        let shift = (0..<4).min { a, b in
            let cost = { (s: Int) in (0..<4).reduce(0) { $0 + points[($1 + s) % 4].distance(to: targets[$1]) } }
            return cost(a) < cost(b)
        } ?? 0
        return Quad(topLeft: points[shift], topRight: points[(shift + 1) % 4],
                    bottomRight: points[(shift + 2) % 4], bottomLeft: points[(shift + 3) % 4])
    }

    var path: Path {
        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        return path
    }
}
