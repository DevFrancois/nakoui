/// The bar pattern of an EAN-13 code, per GS1, so the placeholder backdrop
/// shows a real barcode the decoder can read in the Simulator.
nonisolated enum EAN13Modules {
    /// Set A (odd parity) patterns; 1 is a bar. Set C is their inverse and
    /// set B their mirrored inverse.
    private static let setA = ["0001101", "0011001", "0010011", "0111101", "0100011",
                               "0110001", "0101111", "0111011", "0110111", "0001011"]
    /// Which left-half digits use set B, by the first digit (which isn't drawn).
    private static let firstDigitParity = ["AAAAAA", "AABABB", "AABBAB", "AABBBA", "ABAABB",
                                           "ABBAAB", "ABBBAA", "ABABAB", "ABABBA", "ABBABA"]

    /// The 95 modules from the start guard to the end guard, true for bars.
    /// Nil unless `code` is 13 digits.
    static func modules(for code: String) -> [Bool]? {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == 13, code.count == 13 else { return nil }
        let parity = Array(firstDigitParity[digits[0]])
        var pattern = "101"
        for (index, digit) in digits[1...6].enumerated() {
            pattern += parity[index] == "A" ? setA[digit] : String(setC(digit).reversed())
        }
        pattern += "01010"
        for digit in digits[7...12] {
            pattern += setC(digit)
        }
        pattern += "101"
        return pattern.map { $0 == "1" }
    }

    private static func setC(_ digit: Int) -> String {
        String(setA[digit].map { $0 == "1" ? "0" : "1" })
    }
}
