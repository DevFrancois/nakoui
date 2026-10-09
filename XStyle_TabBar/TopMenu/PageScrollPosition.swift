import SwiftUI

/// Where a page's vertical scroll stands, within the content's real range:
/// a page bouncing past either end reports the end it's bouncing on, so
/// bounces never read as scrolling.
struct PageScrollPosition: Equatable {
    /// Distance scrolled from the top of the content.
    var offset: CGFloat

    init(_ geometry: ScrollGeometry) {
        let offset = geometry.contentOffset.y + geometry.contentInsets.top
        let maximumOffset = geometry.contentSize.height + geometry.contentInsets.top
            + geometry.contentInsets.bottom - geometry.containerSize.height
        self.offset = min(max(offset, 0), max(maximumOffset, 0))
    }
}
