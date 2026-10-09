/// A symbol or half symbol found in an element run, in run positions (1/32 sample).
struct RunHit {
    var kind: HitKind
    var format: BarcodeFormat
    /// Full EAN-13/EAN-8: all digits. UPC-E: the 8-digit form. Halves: their digit positions.
    var digits: DigitString
    /// Full: the first bar's leading edge. Halves: the outer guard's first edge.
    var start: Int32
    /// Full: the last bar's trailing edge. Halves: the centre of the middle guard.
    var end: Int32
    /// Module width in 1/32 sample, on average and next to the middle guard (where stitched
    /// halves meet, so perspective cannot pull them apart).
    var module: Float
    var middleModule: Float
}
