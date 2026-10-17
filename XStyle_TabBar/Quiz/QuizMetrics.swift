import Foundation

/// Shared sizes and timings, so every quiz feels like part of one set.
enum QuizMetrics {
    static let cardCornerRadius = 28.0
    static let answerCornerRadius = 20.0
    static let sectionSpacing = 16.0
    /// A single column stays readable; wide rounds can use two columns.
    static let contentMaxWidth = 600.0
    static let expandedContentMaxWidth = 960.0
    static let hubMaxWidth = 720.0
    static let iconSize = 56.0
    /// How far a Dog or Cat? card must be flung to count as an answer.
    static let swipeThreshold = 110.0
    /// Points of drag per degree of tilt on a Dog or Cat? card.
    static let swipeTiltDivisor = 18.0
    /// Time allowed per lightning question.
    static let lightningDuration: TimeInterval = 8
    /// How long a lightning verdict stays before the next question.
    static let verdictDuration: TimeInterval = 1.6
}
