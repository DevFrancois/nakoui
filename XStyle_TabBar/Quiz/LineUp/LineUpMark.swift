import Foundation

/// How a placed pet fared once the line-up is checked.
enum LineUpMark: Equatable {
    case correct
    /// In the wrong slot; it belongs at this position, counting from 1.
    case wrong(belongsAt: Int)

    /// The shared answer look: green or red glass, with a matching symbol.
    var choiceState: ChoiceState {
        self == .correct ? .correct : .wrong
    }

    var accessibilityDescription: LocalizedStringResource {
        switch self {
        case .correct: "In the right place"
        case .wrong(let position): "Belongs at position \(position)"
        }
    }
}
