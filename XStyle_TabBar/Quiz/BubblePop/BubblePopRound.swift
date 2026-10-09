import Foundation

/// One Bubble Pop round: a rule to pop by, the words that fit it, the
/// decoys that don't, and a fact for the verdict.
struct BubblePopRound: Identifiable {
    let id = UUID()
    let rule: LocalizedStringResource
    let symbol: String
    let words: [BubblePopWord]
    let fact: LocalizedStringResource

    init(
        rule: LocalizedStringResource,
        symbol: String,
        matches: [LocalizedStringResource],
        decoys: [LocalizedStringResource],
        fact: LocalizedStringResource
    ) {
        self.rule = rule
        self.symbol = symbol
        self.words = matches.map { BubblePopWord(text: $0, isMatch: true) }
            + decoys.map { BubblePopWord(text: $0, isMatch: false) }
        self.fact = fact
    }

    var matchCount: Int {
        words.count(where: \.isMatch)
    }
}
