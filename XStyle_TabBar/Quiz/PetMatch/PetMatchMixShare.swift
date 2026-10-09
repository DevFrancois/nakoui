import Foundation

/// One breed's share of a player's answers, for the breed mix on the results.
struct PetMatchMixShare: Identifiable, Equatable {
    let breed: PetMatchBreed
    /// A whole percent; every share in a mix adds up to exactly 100.
    let percent: Int

    var id: PetMatchBreed {
        breed
    }

    /// The share from 0 to 1, for percent formatting.
    var fraction: Double {
        Double(percent) / 100
    }
}
