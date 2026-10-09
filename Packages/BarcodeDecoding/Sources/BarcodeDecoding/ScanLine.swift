/// One straight scanline: which pixels feed each sample and where the samples sit in the image.
///
/// Each sample sums `averaging` pixels taken across the scan direction (along the bars). Diagonal
/// lines interleave half-step samples, so their samples are 0.71 px apart instead of 1.41 px.
struct ScanLine {
    var family: ScanFamily
    /// Perpendicular position of the line in pixels; lines closer than the averaging width are
    /// not independent.
    var offset: Double
    /// Byte offset of the first pixel of sample 0.
    var firstPixel: Int
    /// Byte step between full samples.
    var step: Int
    /// Byte step between the pixels summed into one sample.
    var across: Int
    var sampleCount: Int
    /// Image position (continuous coordinates) of sample 0 and the displacement per sample.
    var originX: Double
    var originY: Double
    var stepX: Double
    var stepY: Double
    /// Whether the line begins/ends at the image border, where a bar edge may be the last thing
    /// visible and the missing quiet zone is given the benefit of the doubt.
    var startsAtBorder: Bool
    var endsAtBorder: Bool

    var isDiagonal: Bool { family == .diagonal || family == .antiDiagonal }

    /// Pixels per sample along the line.
    var sampleLength: Double { isDiagonal ? 0.5.squareRoot() : 1 }

    /// Image point of a position measured in samples.
    func point(at position: Double) -> BarcodePoint {
        BarcodePoint(x: originX + position * stepX, y: originY + position * stepY)
    }
}
