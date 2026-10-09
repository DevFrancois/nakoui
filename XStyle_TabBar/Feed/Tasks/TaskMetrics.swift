import SwiftUI

/// Sizes, spacing and timing shared by the task stack, its cards and the task
/// sheet.
enum TaskMetrics {
    static let cornerRadius: CGFloat = 26
    /// Between the cards in the sheet.
    static let cardSpacing: CGFloat = 16
    /// Between a card's symbol and its text.
    static let summarySpacing: CGFloat = 16
    static let textSpacing: CGFloat = 4
    static let iconWidth: CGFloat = 44
    /// The action button's capsule, sized like the reference design's.
    static let actionButtonHorizontalPadding: CGFloat = 14
    static let actionButtonVerticalPadding: CGFloat = 6
    /// The accent color's share of the action button's fill. Light mode
    /// matches the reference exactly.
    static let actionFillOpacityLight = 0.16
    static let actionFillOpacityDark = 0.3
    static let dismissCircleSize: CGFloat = 26

    /// How many cards the For you stack draws: the front one and up to two
    /// behind it, like a stack of notifications.
    static let visibleStackCount = 3
    /// How far each card behind shows below the one in front of it.
    static let stackPeek: CGFloat = 10
    /// How much narrower each card behind is than the one in front of it.
    static let stackScaleStep: CGFloat = 0.05
    /// How much each card behind is dimmed, out of the deepest card's full dim.
    static let stackDimStep = 0.5

    /// Cards leaving, and the card behind growing into place.
    static let stackAnimation = Animation.smooth(duration: 0.4)
}
