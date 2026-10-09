import Foundation

/// Two faces that belong together, such as a breed and its homeland. The
/// first is the animal, the second its match.
struct PawPairsPair {
    let first: PawPairsFace
    let second: PawPairsFace

    init(_ first: PawPairsFace, _ second: PawPairsFace) {
        self.first = first
        self.second = second
    }
}
