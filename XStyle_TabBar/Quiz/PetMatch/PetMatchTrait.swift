import Foundation

/// One word that sums up a breed, shown as a chip on the results. Its
/// symbol is unique within a breed, so it doubles as the ID. Nonisolated so
/// the nonisolated `PetMatchBreed` can build it.
nonisolated struct PetMatchTrait: Identifiable {
    let title: LocalizedStringResource
    let symbol: String

    var id: String {
        symbol
    }
}
