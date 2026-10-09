/// Up to 13 decimal digits packed four bits each (digit `i` in bits `4i..<4i+4`), so symbols
/// and half symbols can be stored, compared and merged without allocating.
struct DigitString: Equatable {
    private(set) var bits: UInt64 = 0
    /// One bit per digit position that holds a decoded digit.
    private(set) var filled: UInt16 = 0

    subscript(index: Int) -> Int {
        get { Int((bits >> UInt64(4 * index)) & 0xF) }
        set {
            let shift = UInt64(4 * index)
            bits = (bits & ~(0xF << shift)) | (UInt64(newValue) << shift)
            filled |= 1 << UInt16(index)
        }
    }

    /// The union of two digit strings that fill disjoint positions.
    func merged(with other: DigitString) -> DigitString {
        var result = self
        result.bits |= other.bits
        result.filled |= other.filled
        return result
    }

    /// Whether every position `other` fills holds the same digit here.
    func agrees(with other: DigitString) -> Bool {
        var mask: UInt64 = 0
        for i in 0..<16 where other.filled & (1 << UInt16(i)) != 0 { mask |= 0xF << UInt64(4 * i) }
        return filled & other.filled == other.filled && bits & mask == other.bits
    }

    /// GS1 mod-10 check over the first `count` digits, the last of which is the check digit.
    func hasValidCheckDigit(count: Int) -> Bool {
        var sum = 0
        for i in 0..<(count - 1) { sum += self[i] * ((count - 1 - i) & 1 == 1 ? 3 : 1) }
        return (10 - sum % 10) % 10 == self[count - 1]
    }

    func text(count: Int) -> String {
        var scalars = String.UnicodeScalarView()
        for i in 0..<count { scalars.append(Unicode.Scalar(UInt8(48 + self[i]))) }
        return String(scalars)
    }
}
