import Foundation

/// A pet the profile shows. Illustrative until pets can be added.
struct PetProfile: Identifiable {
    let id: String
    let name: String
    let species: LocalizedStringResource
    let symbol: String

    static let samples = [
        PetProfile(id: "biscuit", name: "Biscuit", species: "Dog", symbol: "dog.fill"),
        PetProfile(id: "miso", name: "Miso", species: "Cat", symbol: "cat.fill"),
        PetProfile(id: "pepper", name: "Pepper", species: "Rabbit", symbol: "hare.fill"),
    ]

    /// The id of the pet the profile shows, kept across launches.
    static let storageKey = "profile.selectedPet"
    static let defaultID = samples[0].id

    /// The pet for a stored id; the first for one no longer known.
    static func pet(for id: ID) -> PetProfile {
        samples.first { $0.id == id } ?? samples[0]
    }
}
