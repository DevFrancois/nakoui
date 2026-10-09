import SwiftUI

/// How an answer shows once its question is settled: the right answer turns
/// green, a wrong pick red, and the rest step back.
enum ChoiceState: Equatable {
    case idle
    case correct
    case wrong
    case dimmed

    var glass: Glass {
        switch self {
        case .idle: .regular.interactive()
        case .correct: .regular.tint(.green.opacity(0.35))
        case .wrong: .regular.tint(.red.opacity(0.35))
        case .dimmed: .regular
        }
    }

    /// Shown beside the answer, so the result doesn't rely on color alone.
    var symbol: String? {
        switch self {
        case .correct: "checkmark.circle.fill"
        case .wrong: "xmark.circle.fill"
        case .idle, .dimmed: nil
        }
    }

    var symbolTint: Color {
        self == .wrong ? .red : .green
    }

    var accessibilityValue: LocalizedStringResource {
        switch self {
        case .correct: "Correct answer"
        case .wrong: "Your answer, incorrect"
        case .idle, .dimmed: ""
        }
    }
}
