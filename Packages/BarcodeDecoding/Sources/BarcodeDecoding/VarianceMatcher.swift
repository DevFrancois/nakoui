/// zxing-cpp's digit classifier (Apache-2.0): the four widths, normalised to 7 modules, against
/// every candidate pattern; each element may deviate by at most 0.7 module and the mean deviation
/// must stay below 0.48 module per module. Used only where the like-edge classifier cannot decide.
enum VarianceMatcher {
    private static let maxIndividual: Float = 0.7
    private static let maxAverage: Float = 0.48

    /// The best digit for widths in reading order, with whether it is from the even (G) set.
    /// Space-first characters try the L and G sets; bar-first (R) characters the L widths only.
    static func match(_ e0: Float, _ e1: Float, _ e2: Float, _ e3: Float, barFirst: Bool) -> (digit: Int, isEven: Bool)? {
        let total = e0 + e1 + e2 + e3
        let unit = total / 7
        var best = maxAverage, result: (Int, Bool)?
        for set in 0..<(barFirst ? 1 : 2) {
            let even = set == 1
            for digit in 0..<10 {
                let packed = oddWidths(digit)
                var widths = (Float((packed >> 12) & 0xF), Float((packed >> 8) & 0xF), Float((packed >> 4) & 0xF), Float(packed & 0xF))
                if even { widths = (widths.3, widths.2, widths.1, widths.0) }
                let d0 = abs(e0 - widths.0 * unit), d1 = abs(e1 - widths.1 * unit)
                let d2 = abs(e2 - widths.2 * unit), d3 = abs(e3 - widths.3 * unit)
                guard max(max(d0, d1), max(d2, d3)) <= maxIndividual * unit else { continue }
                let score = (d0 + d1 + d2 + d3) / total
                if score < best {
                    best = score
                    result = (digit, even)
                }
            }
        }
        return result
    }

    /// L-set widths of a digit as four 4-bit nibbles, first element in the top nibble.
    private static func oddWidths(_ digit: Int) -> Int {
        switch digit {
        case 0: 0x3211
        case 1: 0x2221
        case 2: 0x2122
        case 3: 0x1411
        case 4: 0x1132
        case 5: 0x1231
        case 6: 0x1114
        case 7: 0x1312
        case 8: 0x1213
        default: 0x3112
        }
    }
}
