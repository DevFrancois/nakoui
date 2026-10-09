import SwiftUI

/// The two animals the quizzes are about. Nonisolated so it can serve as a
/// glass effect ID, which must be sendable.
nonisolated enum PetSpecies: CaseIterable {
    case dog
    case cat

    var title: LocalizedStringResource {
        switch self {
        case .dog: "Dog"
        case .cat: "Cat"
        }
    }

    var symbol: String {
        switch self {
        case .dog: "dog.fill"
        case .cat: "cat.fill"
        }
    }

    var tint: Color {
        switch self {
        case .dog: .orange
        case .cat: .purple
        }
    }
}
