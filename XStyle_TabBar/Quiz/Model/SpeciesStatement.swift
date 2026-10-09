import Foundation

/// A fact that belongs to dogs or to cats, for the Dog or Cat? deck.
struct SpeciesStatement: Identifiable {
    let id = UUID()
    let text: LocalizedStringResource
    let species: PetSpecies
    let fact: LocalizedStringResource
}
