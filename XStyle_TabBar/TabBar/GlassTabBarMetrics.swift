import Foundation

enum GlassTabBarMetrics {
    // Preferred content dimensions, not assumptions about the system toolbar.
    // Padding can compress; each destination's touch target cannot.
    static let preferredHorizontalWidth: CGFloat = 326
    // The horizontal toolbar centers its item. Extra space below the capsule
    // raises it 14 points without adding space inside the glass or touch anchor.
    static let horizontalToolbarBottomPadding: CGFloat = 28
    static let minimumHorizontalWidth = minimumTapSize * CGFloat(RootTab.allCases.count)
    // Duo's vertical menu uses a wider capsule and taller, icon-only rows.
    // The 44-point touch minimum is a fallback, not the preferred row size.
    static let preferredVerticalWidth: CGFloat = 60
    static let verticalItemHeight: CGFloat = 58
    static let verticalHorizontalInset: CGFloat = 8
    static let minimumHeight: CGFloat = 64
    static let contentInset: CGFloat = 6
    static let minimumTapSize: CGFloat = 44
    static let itemPadding: CGFloat = 4
    static let labelSpacing: CGFloat = 4
    static let symbolSize: CGFloat = 23
    static let maximumSymbolSize: CGFloat = 34
    static let labelSize: CGFloat = 9
}
