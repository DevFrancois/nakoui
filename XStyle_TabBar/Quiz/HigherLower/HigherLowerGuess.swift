import SwiftUI

/// The call on the challenger: is its value higher or lower than the known
/// pet's? Nonisolated so it can serve as a glass effect ID, which must be
/// sendable.
nonisolated enum HigherLowerGuess: CaseIterable {
    case higher
    case lower

    var symbol: String {
        switch self {
        case .higher: "arrow.up"
        case .lower: "arrow.down"
        }
    }

    /// Warm for up, cool for down, and clear of the green and red that
    /// mark right and wrong.
    var tint: Color {
        switch self {
        case .higher: .orange
        case .lower: .teal
        }
    }
}
