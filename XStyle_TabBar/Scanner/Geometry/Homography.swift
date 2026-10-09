import SwiftUI

/// A 2D projective transform in SwiftUI's row-vector convention, laid out
/// exactly like `ProjectionTransform`:
///
///     [x' y' w'] = [x y 1] * | m11 m12 m13 |
///                            | m21 m22 m23 |
///                            | m31 m32 m33 |
///
///     X = x' / w',  Y = y' / w'
///
/// m31/m32 are the translation and m13/m23 the perspective terms;
/// `a.concatenating(b)` applies `a`, then `b`, like CGAffineTransform.
nonisolated struct Homography: Equatable, Sendable {
    var m11: Double, m12: Double, m13: Double
    var m21: Double, m22: Double, m23: Double
    var m31: Double, m32: Double, m33: Double

    static let identity = Homography(m11: 1, m12: 0, m13: 0, m21: 0, m22: 1, m23: 0, m31: 0, m32: 0, m33: 1)

    /// Maps the unit square (0,0) (1,0) (1,1) (0,1) onto the quad's corners,
    /// after Heckbert's square-to-quadrilateral solution ("Fundamentals of
    /// Texture Mapping and Image Warping", 1989). Nil when corners are collinear.
    static func unitSquare(to q: Quad) -> Homography? {
        let x0 = Double(q.topLeft.x), y0 = Double(q.topLeft.y)
        let x1 = Double(q.topRight.x), y1 = Double(q.topRight.y)
        let x2 = Double(q.bottomRight.x), y2 = Double(q.bottomRight.y)
        let x3 = Double(q.bottomLeft.x), y3 = Double(q.bottomLeft.y)
        let sx = x0 - x1 + x2 - x3
        let sy = y0 - y1 + y2 - y3

        // x = (a u + b v + c) / (g u + h v + 1), y = (d u + e v + f) / (g u + h v + 1)
        let a, b, c, d, e, f, g, h: Double
        if abs(sx) < 1e-12, abs(sy) < 1e-12 {
            // A parallelogram: the map is affine.
            a = x1 - x0; b = x2 - x1; c = x0
            d = y1 - y0; e = y2 - y1; f = y0
            g = 0; h = 0
        } else {
            let dx1 = x1 - x2, dx2 = x3 - x2
            let dy1 = y1 - y2, dy2 = y3 - y2
            let den = dx1 * dy2 - dx2 * dy1
            guard abs(den) > 1e-12 else { return nil }
            g = (sx * dy2 - dx2 * sy) / den
            h = (dx1 * sy - sx * dy1) / den
            a = x1 - x0 + g * x1
            b = x3 - x0 + h * x3
            c = x0
            d = y1 - y0 + g * y1
            e = y3 - y0 + h * y3
            f = y0
        }
        return Homography(m11: a, m12: d, m13: g, m21: b, m22: e, m23: h, m31: c, m32: f, m33: 1)
    }

    /// Maps `rect`'s corners onto `q`. For a view's own projection, pass its
    /// local bounds and `q` in the same local coordinates.
    static func rect(_ rect: CGRect, to q: Quad) -> Homography? {
        guard rect.width > 0, rect.height > 0, let square = unitSquare(to: q) else { return nil }
        let normalize = Homography(
            m11: 1 / Double(rect.width), m12: 0, m13: 0,
            m21: 0, m22: 1 / Double(rect.height), m23: 0,
            m31: -Double(rect.minX) / Double(rect.width), m32: -Double(rect.minY) / Double(rect.height), m33: 1
        )
        return normalize.concatenating(square)
    }

    /// Applies `self`, then `r`.
    func concatenating(_ r: Homography) -> Homography {
        Homography(
            m11: m11 * r.m11 + m12 * r.m21 + m13 * r.m31,
            m12: m11 * r.m12 + m12 * r.m22 + m13 * r.m32,
            m13: m11 * r.m13 + m12 * r.m23 + m13 * r.m33,
            m21: m21 * r.m11 + m22 * r.m21 + m23 * r.m31,
            m22: m21 * r.m12 + m22 * r.m22 + m23 * r.m32,
            m23: m21 * r.m13 + m22 * r.m23 + m23 * r.m33,
            m31: m31 * r.m11 + m32 * r.m21 + m33 * r.m31,
            m32: m31 * r.m12 + m32 * r.m22 + m33 * r.m32,
            m33: m31 * r.m13 + m32 * r.m23 + m33 * r.m33
        )
    }

    func apply(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        let w = x * m13 + y * m23 + m33
        return CGPoint(x: (x * m11 + y * m21 + m31) / w, y: (x * m12 + y * m22 + m32) / w)
    }

    /// Same layout and convention as SwiftUI's type, so the fields copy across.
    var projectionTransform: ProjectionTransform {
        var t = ProjectionTransform()
        t.m11 = m11; t.m12 = m12; t.m13 = m13
        t.m21 = m21; t.m22 = m22; t.m23 = m23
        t.m31 = m31; t.m32 = m32; t.m33 = m33
        return t
    }
}
