/// The bars and spaces of one scanline in one reading direction: element 0 is a space (zero
/// wide if the line starts on a bar), colours alternate, and the last element is a space.
/// Positions are in 1/32 sample, measured along the reading direction.
struct ElementRun {
    /// `starts[i]` is where element `i` begins; `starts[count]` is the end of the line.
    let starts: UnsafeMutablePointer<Int32>
    let widths: UnsafeMutablePointer<Int32>
    /// Slope of the edge at `starts[i]` (0 at the line ends).
    let strengths: UnsafeMutablePointer<Int32>
    var count = 0
    /// Whether the first/last space runs into the image border (an unbounded quiet zone).
    var leadingUnbounded = false
    var trailingUnbounded = false
    /// Whether this run reads the scanline backwards.
    var isReversed = false
    /// For a reversed run, `lineEnd - position` maps a run position back onto the line.
    var lineEnd: Int32 = 0
    /// One pixel along the line, in run units.
    var onePixel: Int32 = EdgeList.one

    init(capacity: Int) {
        starts = .allocate(capacity: capacity + 1)
        widths = .allocate(capacity: capacity)
        strengths = .allocate(capacity: capacity + 1)
    }

    func deallocate() {
        starts.deallocate()
        widths.deallocate()
        strengths.deallocate()
    }

    /// Builds the forward run of a line from its edges.
    mutating func build(from edges: EdgeList, line: ScanLine) {
        let lineStart = -EdgeList.one / 2
        let end = Int32(line.sampleCount) * EdgeList.one - EdgeList.one / 2
        var n = 0
        starts[0] = lineStart
        strengths[0] = 0
        n = 1
        if edges.startsDark {
            // A zero-width space, then the bar the line starts on.
            starts[1] = lineStart
            strengths[1] = 0
            n = 2
        }
        for i in 0..<edges.count {
            starts[n] = edges.positions[i]
            strengths[n] = edges.strengths[i]
            n &+= 1
        }
        if n & 1 == 0 {
            // The line ends on a bar: close it with a zero-width space.
            starts[n] = end
            strengths[n] = 0
            n &+= 1
        }
        starts[n] = end
        strengths[n] = 0
        for i in 0..<n { widths[i] = starts[i &+ 1] &- starts[i] }
        count = n
        leadingUnbounded = line.startsAtBorder && !edges.startsDark
        trailingUnbounded = line.endsAtBorder && widths[n &- 1] > 0
        isReversed = false
        lineEnd = end &+ lineStart
        onePixel = Int32((Double(EdgeList.one) / line.sampleLength).rounded())
    }

    /// Builds the backward run of `run`.
    mutating func buildReversed(of run: ElementRun) {
        let n = run.count
        let mirror = run.lineEnd
        for i in 0...n {
            starts[i] = mirror &- run.starts[n &- i]
            strengths[i] = run.strengths[n &- i]
        }
        for i in 0..<n { widths[i] = run.widths[n &- 1 &- i] }
        count = n
        leadingUnbounded = run.trailingUnbounded
        trailingUnbounded = run.leadingUnbounded
        isReversed = true
        lineEnd = mirror
        onePixel = run.onePixel
    }

    /// Position along the scanline, in samples, of a run position.
    @inline(__always)
    func linePosition(_ position: Int32) -> Double {
        Double(isReversed ? lineEnd &- position : position) / Double(EdgeList.one)
    }
}
