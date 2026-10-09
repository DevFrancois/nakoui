import SwiftUI

/// How a card shows on the table. Results carry a symbol and words as well as
/// a tint, so they never rely on color alone.
enum PawPairsCardState: Equatable {
    case faceDown
    case faceUp
    /// Turned up with a card it doesn't match, before both turn back.
    case missed
    case matched

    var isFaceUp: Bool {
        self != .faceDown
    }

    /// The face-down side: the game's color, answering the touch.
    static var backGlass: Glass {
        .regular.tint(QuizKind.pawPairs.tint.opacity(0.55)).interactive()
    }

    var frontGlass: Glass {
        switch self {
        case .matched: .regular.tint(.green.opacity(0.35))
        case .missed: .regular.tint(.red.opacity(0.3))
        case .faceUp, .faceDown: .regular
        }
    }

    var badgeSymbol: String? {
        switch self {
        case .matched: "checkmark.circle.fill"
        case .missed: "xmark.circle.fill"
        case .faceDown, .faceUp: nil
        }
    }

    var badgeTint: Color {
        self == .missed ? .red : .green
    }

    var accessibilityValue: LocalizedStringResource {
        switch self {
        case .matched: "Matched"
        case .missed: "Not a match"
        case .faceDown, .faceUp: ""
        }
    }
}
