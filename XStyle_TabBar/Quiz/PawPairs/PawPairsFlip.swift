import SwiftUI

/// What turning a card over did.
enum PawPairsFlip: Equatable {
    /// The first card of a move.
    case turned
    case matched
    case missed

    var feedback: SensoryFeedback {
        switch self {
        case .turned: .selection
        case .matched: .success
        case .missed: .impact(flexibility: .soft, intensity: 0.6)
        }
    }
}
