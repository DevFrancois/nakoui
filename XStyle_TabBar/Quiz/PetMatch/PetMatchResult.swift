import Foundation

/// How a round of Which Dog Are You? turned out. A value rather than the
/// live tally, so the results keep showing this match while "Take it again"
/// clears the tally and the results animate away.
struct PetMatchResult: Equatable {
    let match: PetMatchBreed
    let runnerUp: PetMatchBreed
    /// Each breed the answers leaned toward, best first, adding up to 100%.
    let mix: [PetMatchMixShare]
}
