import SwiftUI

/// Timings and accents for Which Dog Are You?, alongside the shared `QuizMetrics`.
enum PetMatchMetrics {
    /// How long a pick stays highlighted before the next question.
    static let pickBeat = Duration.milliseconds(650)
    /// How long the match is sniffed out before the reveal.
    static let sniffDuration = Duration.seconds(1.8)
    /// How often the emblems change while the match is sniffed out.
    static let shuffleInterval = Duration.milliseconds(170)
    /// The gap between mood tiles, and the distance at which their glass
    /// starts to blend, so the four moods stay apart at rest.
    static let tileSpacing = 12.0
    /// The accent of each tile position, so every question looks like a mood board.
    static let tileTints: [Color] = [.orange, .cyan, .indigo, .mint]

    static func tileTint(at index: Int) -> Color {
        tileTints[index % tileTints.count]
    }
}
