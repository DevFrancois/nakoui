import Foundation

/// Word Wag's sizes and timings. Nonisolated so the keyframe animations,
/// which run outside the main actor, can read them.
nonisolated enum WordWagMetrics {
    /// A tile's side at the default text size. It grows with Dynamic Type
    /// and shrinks to fit narrow windows, down to the minimum tap size.
    static let tileSize = 52.0
    /// Below this share of the preferred size, tiles wrap onto more rows
    /// rather than shrink, so letters stay big at large text sizes.
    static let smallestTileScale = 0.7
    /// Tight enough that seven tiles fit across the narrowest iPhone.
    static let tileSpacing = 5.0
    static let tileCornerRadius = 14.0
    /// Between the answer slots and the tray.
    static let traySpacing = 28.0
    /// How close tiles must come before their glass melts together. Less
    /// than the spacing, so resting tiles stay apart while moving ones blend.
    static let looseBlend = 2.0
    /// Enough to fuse a solved word into one piece of glass.
    static let fusedBlend = 16.0
    /// Between the Hint, Shuffle and Give up capsules. With
    /// `controlPadding`, tight enough that all three fit in a row across a
    /// 375-point iPhone at the default text size.
    static let controlSpacing = 8.0
    /// Inside each control capsule, beside its title. Any room the row has
    /// to spare is shared out on top of this.
    static let controlPadding = 8.0
    /// How close the controls and cards under the board must come before
    /// their glass blends. Less than `controlSpacing`, so the capsules stay
    /// separate at rest; matching glass IDs still morph, such as Hint into
    /// its clue card.
    static let panelBlend = 6.0
    /// Lets the last tile land before a guess shakes or celebrates.
    static let landingPause = 0.25
    /// Between one tile's hop and the next in the celebration wave.
    static let hopStagger = 0.07
    /// Lets the fact card morph in before scrolling it and Next into view.
    static let nextScrollDelay = 0.5
}
