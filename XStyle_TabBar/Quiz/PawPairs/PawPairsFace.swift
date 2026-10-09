import Foundation

/// What one card shows once it's turned over: a word and a small symbol.
struct PawPairsFace {
    let text: LocalizedStringResource
    let symbol: String

    init(_ text: LocalizedStringResource, symbol: String) {
        self.text = text
        self.symbol = symbol
    }
}
