import SwiftUI

/// Sizes and timings for Line 'Em Up, alongside the shared `QuizMetrics`.
enum LineUpMetrics {
    /// Glass closer than this blends: a slot's number merges with the pet
    /// placed beside it, while rows and pool chips stay apart.
    static let glassSpacing = 10.0
    /// Between a slot's number and its pet; inside `glassSpacing`.
    static let badgeGap = 6.0
    /// Between slots, and between pool chips; outside `glassSpacing`.
    static let rowSpacing = 12.0
    /// A pet chip or open slot's height at the default text size.
    static let chipHeight = 60.0
    /// A slot's number stops growing here, so at the largest sizes it
    /// doesn't crowd the pet's name.
    static let largestBadgeTypeSize = DynamicTypeSize.accessibility1
    /// The outline of an open slot or an empty pool spot.
    static let dashedOutline = StrokeStyle(lineWidth: 1.5, dash: [6, 6])
    /// Between each slot's verdict as a checked line-up is revealed.
    static let revealInterval = Duration.milliseconds(350)
    /// After the last verdict, before the score and the fact.
    static let verdictDelay = Duration.milliseconds(300)
    /// After the score, so the Check glass has grown into the verdict card
    /// before it's scrolled to or focused.
    static let settlePause = Duration.milliseconds(350)
}
