import SwiftUI

/// How the current question was settled.
enum QuizOutcome: Equatable {
    case correct
    case wrong
    case timedOut

    var title: LocalizedStringResource {
        switch self {
        case .correct: "Correct!"
        case .wrong: "Not quite"
        case .timedOut: "Out of time"
        }
    }

    var symbol: String {
        switch self {
        case .correct: "checkmark.circle.fill"
        case .wrong: "xmark.circle.fill"
        case .timedOut: "timer"
        }
    }

    var tint: Color {
        switch self {
        case .correct: .green
        case .wrong: .red
        case .timedOut: .orange
        }
    }

    var feedback: SensoryFeedback {
        switch self {
        case .correct: .success
        case .wrong: .error
        case .timedOut: .warning
        }
    }
}
