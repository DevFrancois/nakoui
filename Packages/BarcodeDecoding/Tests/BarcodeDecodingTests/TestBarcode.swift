/// Renders exact EAN/UPC bar patterns into a luma buffer, for tests.
struct TestBarcode {
    private static let setA = ["0001101", "0011001", "0010011", "0111101", "0100011",
                               "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let firstDigitParity = ["AAAAAA", "AABABB", "AABBAB", "AABBBA", "ABAABB",
                                           "ABBAAB", "ABBBAA", "ABABAB", "ABABBA", "ABBABA"]
    /// UPC-E number system 0, by check digit. B = even parity.
    private static let upcEParity = ["BBBAAA", "BBABAA", "BBAABA", "BBAAAB", "BABBAA",
                                     "BAABBA", "BAAABB", "BABABA", "BABAAB", "BAABAB"]

    /// Modules from the start guard to the end guard, true for bars.
    let modules: [Bool]

    static func ean13(_ code: String) -> TestBarcode {
        let d = digits(code)
        let parity = Array(firstDigitParity[d[0]])
        var pattern = "101"
        for i in 1...6 { pattern += parity[i - 1] == "A" ? setA[d[i]] : setB(d[i]) }
        pattern += "01010"
        for i in 7...12 { pattern += setC(d[i]) }
        return TestBarcode(pattern: pattern + "101")
    }

    static func ean8(_ code: String) -> TestBarcode {
        let d = digits(code)
        var pattern = "101"
        for i in 0..<4 { pattern += setA[d[i]] }
        pattern += "01010"
        for i in 4..<8 { pattern += setC(d[i]) }
        return TestBarcode(pattern: pattern + "101")
    }

    /// `code` is the 8-digit form: number system 0, six digits, check digit.
    static func upcE(_ code: String) -> TestBarcode {
        let d = digits(code)
        let parity = Array(upcEParity[d[7]])
        var pattern = "101"
        for i in 1...6 { pattern += parity[i - 1] == "A" ? setA[d[i]] : setB(d[i]) }
        return TestBarcode(pattern: pattern + "010101")
    }

    private init(pattern: String) {
        modules = pattern.map { $0 == "1" }
    }

    /// A light image with the code drawn level, bars running down the image
    /// (`rotated` false) or across it, as the portrait camera sees a level code.
    func image(moduleSize: Int = 3, barHeight: Int = 120, rotated: Bool = false) -> [UInt8] {
        let length = (modules.count + 30) * moduleSize
        let size = (width: rotated ? barHeight + 80 : length, height: rotated ? length : barHeight + 80)
        var pixels = [UInt8](repeating: 220, count: size.width * size.height)
        for (index, isBar) in modules.enumerated() where isBar {
            for offset in 0..<moduleSize {
                let along = (index + 15) * moduleSize + offset
                for across in 40..<(40 + barHeight) {
                    // Rotated: the code reads up the image, as in the app.
                    let (x, y) = rotated ? (across, size.height - 1 - along) : (along, across)
                    pixels[y * size.width + x] = 30
                }
            }
        }
        return pixels
    }

    func size(moduleSize: Int = 3, barHeight: Int = 120, rotated: Bool = false) -> (width: Int, height: Int) {
        let length = (modules.count + 30) * moduleSize
        return rotated ? (barHeight + 80, length) : (length, barHeight + 80)
    }

    private static func digits(_ code: String) -> [Int] {
        code.compactMap(\.wholeNumberValue)
    }

    private static func setC(_ digit: Int) -> String {
        String(setA[digit].map { $0 == "1" ? "0" : "1" })
    }

    private static func setB(_ digit: Int) -> String {
        String(setC(digit).reversed())
    }
}
