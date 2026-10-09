/// A 2 x 2 gradient structure tensor [xx xy; xy yy].
struct Tensor {
    var xx = 0.0
    var xy = 0.0
    var yy = 0.0

    /// The dominant orientation as a doubled-angle unit vector (cos 2a, sin 2a), so opposite
    /// gradients agree, and the coherence (0 for no preferred orientation, 1 for straight edges).
    var direction: (cos: Double, sin: Double, coherence: Double) {
        let c = xx - yy, s = 2 * xy
        let norm = (c * c + s * s).squareRoot()
        return norm > 0 ? (c / norm, s / norm, norm / (xx + yy)) : (0, 0, 0)
    }

    /// Whether this orientation could be the code's for a hit decoded along its segment: a
    /// scanline more than about 55 degrees off the reading direction cannot cross a half symbol.
    func isPlausible(along hit: LineHit) -> Bool {
        let d = direction
        guard d.coherence > 0, hit.length > 0 else { return false }
        let ux = (hit.end.x - hit.start.x) / hit.length, uy = (hit.end.y - hit.start.y) / hit.length
        return d.cos * (ux * ux - uy * uy) + d.sin * 2 * ux * uy >= -0.34
    }
}
