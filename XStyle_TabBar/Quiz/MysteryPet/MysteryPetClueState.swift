import Foundation

/// How a clue bubble shows: still being typed, the newest clue, an earlier
/// one, or an extra clue that only came in after the answer.
enum MysteryPetClueState {
    case typing
    case latest
    case earlier
    case extra
}
