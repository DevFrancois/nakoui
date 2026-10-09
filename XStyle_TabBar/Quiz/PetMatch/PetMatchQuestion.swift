import Foundation

/// A playful question with four mood tiles to choose from.
struct PetMatchQuestion: Identifiable {
    let id = UUID()
    let prompt: LocalizedStringResource
    let symbol: String
    let answers: [PetMatchAnswer]
}
