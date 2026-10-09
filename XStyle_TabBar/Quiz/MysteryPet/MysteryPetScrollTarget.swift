import Foundation

/// Where Who Am I? scrolls to: the top for each new mystery pet, and the
/// reveal once the breed is settled, with its fact and Next below it.
nonisolated enum MysteryPetScrollTarget: Hashable {
    case top
    case reveal
}
