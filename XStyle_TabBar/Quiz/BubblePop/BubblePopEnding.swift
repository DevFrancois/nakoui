import Foundation

/// How a Bubble Pop round ended, with a verdict that has a symbol and
/// words, not just a color.
enum BubblePopEnding: Equatable {
    /// Every match popped, without a wrong pop.
    case perfect
    /// Every match popped, with the one forgiven wrong pop.
    case cleared
    /// A second wrong pop.
    case outOfPaws
    case timeUp
    /// Ended with Done before every match was popped.
    case incomplete

    var isCleared: Bool {
        self == .perfect || self == .cleared
    }

    var outcome: QuizOutcome {
        switch self {
        case .perfect, .cleared: .correct
        case .timeUp: .timedOut
        case .outOfPaws, .incomplete: .wrong
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .perfect: "Perfect pop!"
        case .cleared: "Round cleared!"
        case .outOfPaws: "Out of paws!"
        case .timeUp: "Time's up!"
        case .incomplete: "Not quite"
        }
    }

    var symbol: String {
        switch self {
        case .perfect: "star.circle.fill"
        case .cleared: "checkmark.circle.fill"
        case .outOfPaws: "pawprint.circle.fill"
        case .timeUp: "timer"
        case .incomplete: "xmark.circle.fill"
        }
    }
}
