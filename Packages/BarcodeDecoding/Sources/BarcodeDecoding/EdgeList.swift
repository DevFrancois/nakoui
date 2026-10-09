/// Alternating bar/space edges found on one scanline, in sample units with 5 fractional bits.
/// Storage is allocated once and reused; the owner calls `deallocate()`.
struct EdgeList {
    static let fractionBits: Int32 = 5
    static let one: Int32 = 1 << fractionBits

    let positions: UnsafeMutablePointer<Int32>
    /// Slope of each edge (profile units per sample), used to tell real edges from noise.
    let strengths: UnsafeMutablePointer<Int32>
    var count = 0
    /// Whether the first edge goes from dark to light, i.e. the line starts on a bar.
    var startsDark = false

    init(capacity: Int) {
        positions = .allocate(capacity: capacity)
        strengths = .allocate(capacity: capacity)
    }

    func deallocate() {
        positions.deallocate()
        strengths.deallocate()
    }

    @inline(__always)
    mutating func append(position: Int32, strength: Int32) {
        positions[count] = position
        strengths[count] = strength
        count &+= 1
    }

    /// Removes slivers: an element whose two edges are both weaker than `ratio` (in 1/16) of
    /// the strongest edge within two edges on either side, such as a void in a bar or a speck in
    /// a space. Its neighbours merge.
    mutating func removeSlivers(ratio: Int32) {
        guard count >= 4 else { return }
        var kept = 0
        var k = 0
        while k < count {
            if k >= 1 && k + 2 < count {
                let inner = max(strengths[k], strengths[k + 1])
                var outer: Int32 = 0
                for j in max(0, k - 2)..<k { outer = max(outer, strengths[j]) }
                for j in (k + 2)..<min(count, k + 4) { outer = max(outer, strengths[j]) }
                if inner &* 16 < outer &* ratio {
                    k += 2
                    continue
                }
            }
            positions[kept] = positions[k]
            strengths[kept] = strengths[k]
            kept += 1
            k += 1
        }
        count = kept
    }
}
