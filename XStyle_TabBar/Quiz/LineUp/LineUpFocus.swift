import Foundation

/// Where VoiceOver focus goes as the line-up changes, so a placed or
/// returned pet, a full line and a checked one never leave focus stranded.
enum LineUpFocus: Hashable {
    /// The new round's order to make.
    case prompt
    /// A pet waiting in the pool.
    case pet(LineUpPet.ID)
    case check
    case verdict
}
