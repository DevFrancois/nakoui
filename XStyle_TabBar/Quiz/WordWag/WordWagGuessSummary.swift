import SwiftUI

/// An invisible element over the answer slots that reads the guess to
/// VoiceOver as a whole word, with an action to clear it.
struct WordWagGuessSummary: View {
    let board: WordWagBoard

    var body: some View {
        Rectangle()
            .fill(.clear)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text("Your guess"))
            .accessibilityValue(Text(value))
            .accessibilityActions {
                if !board.isSettled {
                    Button("Clear guess", action: clear)
                }
            }
            // Read before the tiles it covers.
            .accessibilitySortPriority(WordWagSpot.guess.accessibilitySortPriority)
    }

    private var value: LocalizedStringResource {
        let filled = board.slots.count { $0 != nil }
        guard filled > 0 else {
            return "Empty, ^[\(board.slots.count) letter](inflect: true) to fill"
        }
        return "\(spokenLetters), \(filled) of \(board.slots.count) letters"
    }

    /// The letters as one word while they run unbroken from the start, so
    /// VoiceOver says it; otherwise letter by letter, with blanks for gaps.
    private var spokenLetters: String {
        let letters = board.slots.map { tileID in
            tileID.map { board.tiles[$0].letter }
        }
        let leading = letters.prefix { $0 != nil }.compactMap { $0 }
        guard let lastPlaced = letters.lastIndex(where: { $0 != nil }), lastPlaced >= leading.count else {
            return leading.joined().localizedCapitalized
        }
        let blank = String(localized: "blank", comment: "VoiceOver's word for an empty answer slot in Word Wag.")
        return letters[...lastPlaced].map { $0 ?? blank }.formatted(.list(type: .and, width: .narrow))
    }

    private func clear() {
        board.clear()
    }
}
