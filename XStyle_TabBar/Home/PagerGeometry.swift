import SwiftUI

/// Where the Home pager's horizontal scroll stands.
struct PagerGeometry: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.x + geometry.contentInsets.leading
        width = geometry.containerSize.width
    }

    var progress: CGFloat {
        width > 0 ? offset / width : 0
    }
}
