import Foundation

/// How an empty spot on the board is drawn. Spots with a tile on them draw
/// nothing, so the outline doesn't show through the glass.
enum WordWagSocketStyle {
    /// An empty answer slot.
    case slot
    /// The empty answer slot the next tray tile will fill.
    case nextSlot
    /// The place a tray tile left.
    case hole
    case hidden
}
