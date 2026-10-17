import SwiftUI

/// Where the Home pager's horizontal scroll stands.
nonisolated struct PagerGeometry: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 0

    init() {}

    init(offset: CGFloat, width: CGFloat) {
        self.offset = offset
        self.width = width
    }

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.x + geometry.contentInsets.leading
        width = geometry.containerSize.width
    }

    var progress: CGFloat {
        width.isFinite && width > 0 && offset.isFinite ? offset / width : 0
    }

    func nearestPageIndex(pageCount: Int) -> Int {
        let position = min(max(progress, 0), CGFloat(max(pageCount - 1, 0)))
        return Int(position.rounded())
    }
}
