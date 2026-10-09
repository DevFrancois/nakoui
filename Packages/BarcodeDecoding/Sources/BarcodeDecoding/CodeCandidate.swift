/// A code seen in the current frame, with the hits that support it. Candidates are pooled by
/// `FrameAccumulator`, so their arrays keep their capacity from frame to frame.
struct CodeCandidate {
    var format: BarcodeFormat = .ean13
    /// EAN-13/EAN-8: all digits. UPC-E: the 8-digit form.
    var digits = DigitString()
    /// Indices into the frame's hits of full decodes, and of the halves of stitched pairs.
    var fullHits: [Int] = []
    var leftHalves: [Int] = []
    var rightHalves: [Int] = []
    var lineCount = 0

    var digitCount: Int { format == .ean13 ? 13 : 8 }

    mutating func reset(format: BarcodeFormat, digits: DigitString) {
        self.format = format
        self.digits = digits
        fullHits.removeAll(keepingCapacity: true)
        leftHalves.removeAll(keepingCapacity: true)
        rightHalves.removeAll(keepingCapacity: true)
        lineCount = 0
    }
}
