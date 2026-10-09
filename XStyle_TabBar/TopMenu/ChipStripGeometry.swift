import SwiftUI

/// The chip strip's live scroll state, read from SwiftUI rather than from its
/// `ScrollPosition`, whose offset is unknown after the user drags.
struct ChipStripGeometry: Equatable {
    var offset: CGFloat = 0
    var viewportWidth: CGFloat = 0
    var contentWidth: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.x + geometry.contentInsets.leading
        viewportWidth = geometry.containerSize.width
        contentWidth = geometry.contentSize.width
    }
}
