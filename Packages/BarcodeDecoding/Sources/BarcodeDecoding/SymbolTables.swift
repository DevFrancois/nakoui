/// GS1 parity tables for EAN-13 and UPC-E, and UPC-E expansion.
/// Parity words list the six characters first-to-last as bits 5...0, 1 meaning the odd (L) set.
enum SymbolTables {
    /// EAN-13 first digit implied by the left half's parity word, or nil.
    static func ean13FirstDigit(parity: Int) -> Int? {
        switch parity {
        case 0b111111: 0
        case 0b110100: 1
        case 0b110010: 2
        case 0b110001: 3
        case 0b101100: 4
        case 0b100110: 5
        case 0b100011: 6
        case 0b101010: 7
        case 0b101001: 8
        case 0b100101: 9
        default: nil
        }
    }

    /// UPC-E (number system 0) check digit implied by the parity word, or nil. Number system 1
    /// is rejected on purpose: its words overlap EAN-13 left-half words.
    static func upcECheckDigit(parity: Int) -> Int? {
        switch parity {
        case 0b000111: 0
        case 0b001011: 1
        case 0b001101: 2
        case 0b001110: 3
        case 0b010011: 4
        case 0b011001: 5
        case 0b011100: 6
        case 0b010101: 7
        case 0b010110: 8
        case 0b011010: 9
        default: nil
        }
    }

    /// Expands UPC-E data digits (`upcE[1...6]`, number system 0) into the 13-digit GTIN whose
    /// last digit is `check`.
    static func expandUPCE(_ upcE: DigitString, check: Int) -> DigitString {
        var gtin = DigitString()
        for i in 0..<13 { gtin[i] = 0 }
        let last = upcE[6]
        gtin[2] = upcE[1]
        gtin[3] = upcE[2]
        switch last {
        case 0...2:
            gtin[4] = last
            gtin[9] = upcE[3]
            gtin[10] = upcE[4]
            gtin[11] = upcE[5]
        case 3:
            gtin[4] = upcE[3]
            gtin[10] = upcE[4]
            gtin[11] = upcE[5]
        case 4:
            gtin[4] = upcE[3]
            gtin[5] = upcE[4]
            gtin[11] = upcE[5]
        default:
            gtin[4] = upcE[3]
            gtin[5] = upcE[4]
            gtin[6] = upcE[5]
            gtin[11] = last
        }
        gtin[12] = check
        return gtin
    }

    /// Parity word of an EAN-13 left half for a first digit (inverse of `ean13FirstDigit`).
    static func ean13Parity(firstDigit: Int) -> Int {
        switch firstDigit {
        case 0: 0b111111
        case 1: 0b110100
        case 2: 0b110010
        case 3: 0b110001
        case 4: 0b101100
        case 5: 0b100110
        case 6: 0b100011
        case 7: 0b101010
        case 8: 0b101001
        default: 0b100101
        }
    }

    /// Parity word of a number-system-0 UPC-E for a check digit (inverse of `upcECheckDigit`).
    static func upcEParity(check: Int) -> Int {
        switch check {
        case 0: 0b000111
        case 1: 0b001011
        case 2: 0b001101
        case 3: 0b001110
        case 4: 0b010011
        case 5: 0b011001
        case 6: 0b011100
        case 7: 0b010101
        case 8: 0b010110
        default: 0b011010
        }
    }

    /// The L-set character of a digit as 7 modules, first module in bit 6, 1 = bar.
    static func oddCharacter(_ digit: Int) -> Int {
        switch digit {
        case 0: 0b0001101
        case 1: 0b0011001
        case 2: 0b0010011
        case 3: 0b0111101
        case 4: 0b0100011
        case 5: 0b0110001
        case 6: 0b0101111
        case 7: 0b0111011
        case 8: 0b0110111
        default: 0b0001011
        }
    }

    /// Writes the symbol's modules (1 = bar) from its start guard to its end guard into
    /// `modules` and returns their count (95, 67 or 51).
    static func modulePattern(format: BarcodeFormat, digits: DigitString, into modules: UnsafeMutablePointer<UInt8>) -> Int {
        var n = 0
        func put(_ bits: Int, _ count: Int) {
            for k in stride(from: count - 1, through: 0, by: -1) {
                modules[n] = UInt8((bits >> k) & 1)
                n += 1
            }
        }
        // R characters are the L modules inverted; G characters are R characters reversed.
        func character(_ digit: Int, odd: Bool, right: Bool) -> Int {
            let l = oddCharacter(digit)
            if odd { return right ? l ^ 0x7F : l }
            var g = 0
            for k in 0..<7 where (l ^ 0x7F) & (1 << k) != 0 { g |= 1 << (6 - k) }
            return g
        }
        put(0b101, 3)
        switch format {
        case .ean13:
            let parity = ean13Parity(firstDigit: digits[0])
            for i in 0..<6 { put(character(digits[i + 1], odd: parity & (1 << (5 - i)) != 0, right: false), 7) }
            put(0b01010, 5)
            for i in 7..<13 { put(character(digits[i], odd: true, right: true), 7) }
            put(0b101, 3)
        case .ean8:
            for i in 0..<4 { put(character(digits[i], odd: true, right: false), 7) }
            put(0b01010, 5)
            for i in 4..<8 { put(character(digits[i], odd: true, right: true), 7) }
            put(0b101, 3)
        case .upcE:
            let parity = upcEParity(check: digits[7])
            for i in 0..<6 { put(character(digits[i + 1], odd: parity & (1 << (5 - i)) != 0, right: false), 7) }
            put(0b010101, 6)
        }
        return n
    }
}
