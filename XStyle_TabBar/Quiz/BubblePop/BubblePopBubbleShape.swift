import SwiftUI

extension Shape where Self == RoundedRectangle {
    /// A bubble's outline: a circle `diameter` points across, or, with no
    /// diameter at accessibility text sizes, a rounded rectangle that grows
    /// to fit its word. Circular corners make the first an exact circle.
    static func bubblePop(diameter: Double?) -> RoundedRectangle {
        RoundedRectangle(
            cornerRadius: diameter.map { $0 / 2 } ?? BubblePopMetrics.wordBubbleCornerRadius,
            style: .circular
        )
    }
}
