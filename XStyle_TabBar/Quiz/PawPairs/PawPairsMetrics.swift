import SwiftUI

/// Sizes and timings for Paw Pairs.
enum PawPairsMetrics {
    /// Space between cards on the board. The glass container uses it too, so
    /// cards stay apart at rest.
    static let cardSpacing = 10.0
    /// The gap between a card and its match once a cleared board lines up in
    /// pairs; their glass joins across it.
    static let pairSeam = 4.0
    static let pairRowSpacing = 14.0
    /// The wait before the first card, so a new board's header lands first.
    static let dealDelay = Duration.milliseconds(250)
    /// Time between cards as a board is dealt.
    static let dealInterval = Duration.milliseconds(45)
    /// How long a mismatched pair stays up before it turns back.
    static let missDelay = Duration.seconds(1)
    /// The pause after the last match, so its bounce lands before the board
    /// lines up in pairs.
    static let clearPause = Duration.milliseconds(600)
    /// The pause before scrolling, or moving VoiceOver, to the verdict, once
    /// it's laid out.
    static let scrollPause = Duration.milliseconds(350)
    static let flipAnimation = Animation.spring(duration: 0.5, bounce: 0.3)
    static let dealAnimation = Animation.bouncy
    static let reviewAnimation = Animation.spring(duration: 0.7, bounce: 0.25)
}
