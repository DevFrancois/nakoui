import Foundation

enum GlassTabBarMetrics {
    static let maximumWidth: CGFloat = 360
    static let minimumWidth = minimumTapSize * CGFloat(RootTab.allCases.count) + contentInset * 2
    static let verticalWidth = minimumTapSize + contentInset * 2
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
