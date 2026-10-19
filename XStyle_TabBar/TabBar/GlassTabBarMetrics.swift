import Foundation

enum GlassTabBarMetrics {
    // Preferred content dimensions, not assumptions about the system toolbar.
    // Padding can compress; each destination's touch target cannot.
    static let preferredHorizontalWidth: CGFloat = 326
    // The horizontal toolbar centers its item. Extra space below the capsule
    // raises it 14 points without adding space inside the glass or touch anchor.
    static let horizontalToolbarBottomPadding: CGFloat = 28
    static let minimumHorizontalWidth = minimumTapSize * CGFloat(RootTab.allCases.count)
    static let preferredVerticalWidth = minimumTapSize + contentInset * 2
    static let minimumHeight: CGFloat = 64
    static let contentInset: CGFloat = 6
    static let minimumTapSize: CGFloat = 44
    static let itemPadding: CGFloat = 4
    static let labelSpacing: CGFloat = 3
    static let symbolSize: CGFloat = 28
    static let maximumSymbolSize: CGFloat = 34
    static let labelSize: CGFloat = 10
    static let selectionDuration: TimeInterval = 0.25
    static let trackingDuration: TimeInterval = 0.12
    static let releaseDuration: TimeInterval = 0.35
    static let pressedScale: CGFloat = 1.04
}
