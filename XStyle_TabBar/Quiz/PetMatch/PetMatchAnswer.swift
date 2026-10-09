import Foundation

/// One mood tile in Which Dog Are You? There are no wrong answers: each
/// suits one breed best and sometimes a second one a little.
struct PetMatchAnswer: Identifiable, Equatable {
    /// Points for the breed an answer suits best.
    static let primaryPoints = 2
    /// Points for the breed it suits a little.
    static let secondaryPoints = 1

    let id = UUID()
    let title: LocalizedStringResource
    let symbol: String
    let primary: PetMatchBreed
    let secondary: PetMatchBreed?

    init(
        _ title: LocalizedStringResource,
        symbol: String,
        suits primary: PetMatchBreed,
        alsoSuits secondary: PetMatchBreed? = nil
    ) {
        self.title = title
        self.symbol = symbol
        self.primary = primary
        self.secondary = secondary
    }

    /// What picking this answer adds to a breed's tally.
    func points(for breed: PetMatchBreed) -> Int {
        if breed == primary {
            Self.primaryPoints
        } else if breed == secondary {
            Self.secondaryPoints
        } else {
            0
        }
    }
}
