import SwiftUI

/// How a mood tile shows: waiting for a pick, picked, or passed over for
/// another. Every state stays interactive, so a change of mind is one tap away.
enum PetMatchTileState: Equatable {
    case idle
    case picked
    case passed

    /// Idle tiles carry a hint of their own accent; the pick glows in the quiz's color.
    func glass(tint: Color) -> Glass {
        switch self {
        case .idle: .regular.tint(tint.opacity(0.15)).interactive()
        case .picked: .regular.tint(QuizKind.petMatch.tint.opacity(0.4)).interactive()
        case .passed: .regular.interactive()
        }
    }
}
