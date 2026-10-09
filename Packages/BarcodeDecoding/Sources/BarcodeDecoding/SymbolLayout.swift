/// Fixed element layout of a symbol (or half symbol) counted from its start guard's first bar.
struct SymbolLayout {
    var format: BarcodeFormat
    /// Whether the layout stops at the middle guard (a half symbol).
    var isHalf: Bool
    /// Elements from the start guard's first bar through the last guard element.
    var elements: Int
    var modules: Int
    /// Space-first characters after the start guard.
    var leftCharacters: Int
    /// Offset of the 5-element middle guard, or 0 when there is none.
    var middleGuard: Int
    /// Bar-first characters after the middle guard.
    var rightCharacters: Int
    /// Offset and element count of the end guard, or 0 when there is none.
    var endGuard: Int
    var endGuardLength: Int

    var characters: Int { leftCharacters + rightCharacters }

    /// Element offset of character `index`.
    func characterStart(_ index: Int) -> Int {
        index < leftCharacters ? 3 + 4 * index : middleGuard + 5 + 4 * (index - leftCharacters)
    }

    static let ean13 = SymbolLayout(format: .ean13, isHalf: false, elements: 59, modules: 95, leftCharacters: 6,
                                    middleGuard: 27, rightCharacters: 6, endGuard: 56, endGuardLength: 3)
    static let ean8 = SymbolLayout(format: .ean8, isHalf: false, elements: 43, modules: 67, leftCharacters: 4,
                                   middleGuard: 19, rightCharacters: 4, endGuard: 40, endGuardLength: 3)
    static let upcE = SymbolLayout(format: .upcE, isHalf: false, elements: 33, modules: 51, leftCharacters: 6,
                                   middleGuard: 0, rightCharacters: 0, endGuard: 27, endGuardLength: 6)
    static let ean13Half = SymbolLayout(format: .ean13, isHalf: true, elements: 32, modules: 50, leftCharacters: 6,
                                        middleGuard: 27, rightCharacters: 0, endGuard: 0, endGuardLength: 0)
    static let ean8Half = SymbolLayout(format: .ean8, isHalf: true, elements: 24, modules: 36, leftCharacters: 4,
                                       middleGuard: 19, rightCharacters: 0, endGuard: 0, endGuardLength: 0)
}
