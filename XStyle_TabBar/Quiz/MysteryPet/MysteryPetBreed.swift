import Foundation

/// A breed to name from clues in its own voice, for Who Am I?
struct MysteryPetBreed: Identifiable {
    let id = UUID()
    let species: PetSpecies
    /// In the pet's own words, from hardest to easiest.
    let clues: [LocalizedStringResource]
    let choices: [LocalizedStringResource]
    let answerIndex: Int
    let fact: LocalizedStringResource

    var name: LocalizedStringResource {
        choices[answerIndex]
    }
}
