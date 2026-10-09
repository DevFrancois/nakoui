import SwiftUI

/// Bubble Pop's timings, sizes and pace, so every round plays alike.
enum BubblePopMetrics {
    /// How long each round lasts, except under VoiceOver, which has no clock.
    static let roundDuration: TimeInterval = 15
    /// When the clock warms to orange.
    static let hurryThreshold: TimeInterval = 5
    /// Wrong pops a player can take; losing the last one ends the round, so
    /// one wrong pop is forgiven.
    static let lives = 2
    /// The count-in before each round: 3, 2, 1, then "Pop!".
    static let countInStart = 3
    static let countInStep = Duration.milliseconds(650)
    static let popCueDuration = Duration.milliseconds(450)
    /// How long the board holds still once a round is decided, so the last
    /// pop plays out before the verdict.
    static let freezeDuration = Duration.milliseconds(700)
    /// How long the verdict takes to land before the screen scrolls to it,
    /// or VoiceOver moves to it.
    static let verdictSettleDelay = Duration.milliseconds(350)
    /// The standard bubble's diameter, before Dynamic Type and each bubble's
    /// own size.
    static let bubbleSize = 84.0
    /// The most a bubble grows with large text, so two still fit side by side.
    static let maximumBubbleSize = 140.0
    /// The range of bubble sizes, relative to the standard one.
    static let bubbleScales = 0.88...1.12
    /// The corners of a bubble that grows to fit its word, at accessibility
    /// text sizes, where words no longer fit inside a circle.
    static let wordBubbleCornerRadius = QuizMetrics.answerCornerRadius
    /// How much bubbles shrink once settled into the verdict grid.
    static let settledScale = 0.85
    /// How close bubbles come before their glass starts to blend.
    static let glassBlendDistance = 6.0
    /// The gap between bubbles in the grid.
    static let gridSpacing = 10.0
    static let playAreaInset = 12.0
    /// The floating play area's height, as a share of the scroll view's
    /// height below its bars, within limits, so the rule, the clock and the
    /// whole tank fit on screen together. The floor keeps short windows
    /// playable with a scroll.
    static let playAreaFraction = 0.6
    static let playAreaHeights = 280.0...620.0
    /// Rising speed in points per second in the first round, and how much
    /// faster each later round gets.
    static let baseSpeed = 50.0
    static let speedStep = 7.0
    /// Delay between bubbles blowing in, after "Pop!".
    static let entranceStagger = 0.04
    /// Light tints for idle bubbles, clear of a verdict's green, orange and red.
    static let bubbleTints: [Color] = [.cyan, .blue, .indigo, .purple, .teal]
}
