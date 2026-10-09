import Foundation

/// Sizes and timings for Higher or Lower.
enum HigherLowerMetrics {
    /// Steps the challenger's value takes as it counts up to its number.
    static let countSteps = 15
    static let countStepDuration = Duration.milliseconds(65)
    /// A beat on the final number before the verdict lands.
    static let verdictPause = Duration.milliseconds(350)
    /// Lets the fact morph out of the tiles before scrolling it into view.
    static let revealScrollDelay = Duration.milliseconds(300)
    /// How far the versus badge reaches into each card, so their glass melts together.
    static let versusOverlap = 16.0
    static let versusSize = 52.0
    static let meterHeight = 10.0
    static let meterMarkWidth = 3.0
    static let tileSpacing = 12.0
}
