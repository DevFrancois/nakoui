/// A symbol or half symbol decoded on one scanline, in image coordinates.
struct LineHit {
    var kind: HitKind
    var format: BarcodeFormat
    var digits: DigitString
    /// Full: the first bar's leading edge. Halves: the outer guard's first edge.
    var start: BarcodePoint
    /// Full: the last bar's trailing edge. Halves: the centre of the middle guard.
    var end: BarcodePoint
    /// Module width along the scanline, in pixels, on average and next to the middle guard.
    var moduleSize: Double
    var middleModuleSize: Double
    var family: ScanFamily
    /// The scanline's perpendicular position, for telling independent lines apart.
    var lineOffset: Double
    /// Unit vector of the scanline's direction.
    var lineDirection: BarcodePoint

    var midpoint: BarcodePoint { BarcodePoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }
    var length: Double { ((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)).squareRoot() }

    /// Whether this hit and `other` come from scanlines that overlap within `averaging` pixels.
    func sharesLine(with other: LineHit, averaging: Int) -> Bool {
        family == other.family && abs(lineOffset - other.lineOffset) < Double(max(1, averaging))
    }
}
