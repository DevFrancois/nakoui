/// Turns a layout's characters into a symbol or half symbol: the parity word gives the EAN-13
/// first digit, the UPC-E check digit, or which half and direction a 6-character half is; the
/// check digit must hold for whole symbols.
enum SymbolAssembler {
    /// `characters[c]` is character c in reading order; `parity` has the left characters' sets
    /// (first character in the top bit, 1 = odd/L); `quiet` is the quiet zone before the start
    /// guard in modules (a half's side decides how much it needs).
    static func assemble(_ layout: SymbolLayout, characters: DigitString, parity: Int, quiet: Float)
        -> (kind: HitKind, digits: DigitString)? {
        var digits = DigitString()
        switch (layout.format, layout.isHalf) {
        case (.ean13, false):
            guard let firstDigit = SymbolTables.ean13FirstDigit(parity: parity) else { return nil }
            digits[0] = firstDigit
            for c in 0..<12 { digits[c + 1] = characters[c] }
            return digits.hasValidCheckDigit(count: 13) ? (.full, digits) : nil
        case (.ean8, false):
            guard parity == 0b1111 else { return nil }
            for c in 0..<8 { digits[c] = characters[c] }
            return digits.hasValidCheckDigit(count: 8) ? (.full, digits) : nil
        case (.upcE, _):
            guard let check = SymbolTables.upcECheckDigit(parity: parity) else { return nil }
            digits[0] = 0
            for c in 0..<6 { digits[c + 1] = characters[c] }
            digits[7] = check
            return SymbolTables.expandUPCE(digits, check: check).hasValidCheckDigit(count: 13) ? (.full, digits) : nil
        case (.ean13, true):
            if let firstDigit = SymbolTables.ean13FirstDigit(parity: parity), quiet >= SymbolParser.leftQuiet {
                digits[0] = firstDigit
                for c in 0..<6 { digits[c + 1] = characters[c] }
                return (.leftHalf, digits)
            }
            // A right half read backwards from its end guard: R characters reversed read as G.
            guard parity == 0, quiet >= SymbolParser.rightHalfQuiet else { return nil }
            for c in 0..<6 { digits[12 - c] = characters[c] }
            return (.rightHalf, digits)
        case (.ean8, true):
            if parity == 0b1111, quiet >= SymbolParser.leftQuiet {
                for c in 0..<4 { digits[c] = characters[c] }
                return (.leftHalf, digits)
            }
            guard parity == 0, quiet >= SymbolParser.rightHalfQuiet else { return nil }
            for c in 0..<4 { digits[7 - c] = characters[c] }
            return (.rightHalf, digits)
        }
    }
}
