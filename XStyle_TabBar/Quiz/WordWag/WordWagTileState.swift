import SwiftUI

/// How a tile looks: plain glass in the tray, a hint of mint once placed,
/// then green for a solve, red for a wrong guess, or orange when revealed.
enum WordWagTileState {
    case tray
    case placed
    case wrong
    case correct
    case revealed

    var glass: Glass {
        switch self {
        case .tray: .regular.interactive()
        case .placed: .regular.tint(QuizKind.wordWag.tint.opacity(0.25)).interactive()
        case .wrong: .regular.tint(.red.opacity(0.35)).interactive()
        case .correct: .regular.tint(.green.opacity(0.4))
        case .revealed: .regular.tint(.orange.opacity(0.3))
        }
    }

    /// Shown on the tile when colors need differentiating without color.
    var symbol: String? {
        switch self {
        case .wrong: "xmark"
        case .correct: "checkmark"
        case .revealed: "eye.fill"
        case .tray, .placed: nil
        }
    }

    var symbolTint: Color {
        switch self {
        case .wrong: .red
        case .revealed: .orange
        default: .green
        }
    }

    var accessibilityValue: LocalizedStringResource {
        switch self {
        case .wrong: "Wrong guess"
        case .correct: "Correct"
        case .revealed: "Revealed"
        case .tray, .placed: ""
        }
    }
}
