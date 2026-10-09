public struct BarcodeReading: Equatable, Sendable {
    public var format: BarcodeFormat
    /// EAN-13: 13 digits (UPC-A has a leading 0). EAN-8: 8 digits.
    /// UPC-E: 8 digits (number system 0, six data digits, check digit).
    public var text: String
    /// The bars' outline, in reading orientation: `topLeft` is where the start guard's first
    /// bar edge meets the top of the bars, `topRight` where the end guard's last bar edge meets
    /// the top, and the bottom corners are at the bottom of the bars (the side where the
    /// human-readable digits are printed). "Top" is to the left of the reading direction.
    /// The corners must span the full bar height, not just the scanlines that decoded.
    public var topLeft: BarcodePoint
    public var topRight: BarcodePoint
    public var bottomRight: BarcodePoint
    public var bottomLeft: BarcodePoint
    /// Independent scanlines in this frame that decoded this code (fully, or by stitching
    /// both halves). Lines closer than `DecoderOptions.averaging` pixels count once.
    public var lineCount: Int
    /// One module's width in pixels along the reading direction.
    public var moduleSize: Double

    public init(format: BarcodeFormat, text: String, topLeft: BarcodePoint, topRight: BarcodePoint,
         bottomRight: BarcodePoint, bottomLeft: BarcodePoint, lineCount: Int, moduleSize: Double) {
        self.format = format
        self.text = text
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.lineCount = lineCount
        self.moduleSize = moduleSize
    }
}
