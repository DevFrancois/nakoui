import SwiftUI

/// How a bubble shows. During play, matches pop and wrong pops turn red; at
/// the verdict, every bubble shows what it was, with a symbol and words as
/// well as a color.
enum BubblePopBubbleStatus: Equatable {
    /// Not blown in yet, during the count-in.
    case waiting
    case floating
    /// A match, popped during play.
    case popped
    /// A decoy popped by mistake.
    case wrong
    /// At the verdict: a match that was popped.
    case found
    /// At the verdict: a match left unpopped.
    case missed
    /// At the verdict: a decoy rightly left alone.
    case avoided

    func glass(tint: Color, isInteractive: Bool) -> Glass {
        let glass: Glass = switch self {
        case .waiting, .floating: .regular.tint(tint.opacity(0.18))
        case .popped, .found: .regular.tint(.green.opacity(0.3))
        case .wrong: .regular.tint(.red.opacity(0.35))
        case .missed: .regular.tint(.orange.opacity(0.35))
        case .avoided: .regular
        }
        return glass.interactive(isInteractive)
    }

    /// Shown above the word, so the result doesn't rely on color alone.
    var symbol: String? {
        switch self {
        case .popped, .found: "checkmark.circle.fill"
        case .wrong: "xmark.circle.fill"
        case .missed: "exclamationmark.circle.fill"
        case .waiting, .floating, .avoided: nil
        }
    }

    var symbolTint: Color {
        switch self {
        case .wrong: .red
        case .missed: .orange
        default: .green
        }
    }

    /// Whether the bubble still takes a tap while the round plays. A wrong
    /// one does, but only shakes again; it isn't counted twice.
    var isTappable: Bool {
        self == .floating || self == .wrong
    }

    /// Whether the word steps back, its part in the round done.
    var isSubdued: Bool {
        self == .popped || self == .avoided
    }

    var accessibilityValue: LocalizedStringResource {
        switch self {
        case .waiting, .floating: ""
        case .popped: "Popped"
        case .wrong: "Wrong pop, not a match"
        case .found: "Popped, a match"
        case .missed: "Missed, a match"
        case .avoided: "Not a match"
        }
    }
}
