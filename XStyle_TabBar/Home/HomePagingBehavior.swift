import SwiftUI

/// The resolved native landing page, copied before leaving the scroll callback.
nonisolated struct PagerTarget: Equatable, Sendable {
    let index: Int
    let width: CGFloat
    let gestureID: UInt64
}

/// Observes the native paging decision without changing its target or properties.
nonisolated struct HomePagingBehavior: ScrollTargetBehavior {
    let gestureID: UInt64
    let pageCount: Int
    let onTarget: @MainActor @Sendable (PagerTarget) -> Void

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        PagingScrollTargetBehavior().updateTarget(&target, context: context)
        let width = context.containerSize.width
        guard width.isFinite, width > 0, target.rect.minX.isFinite else { return }
        let geometry = PagerGeometry(offset: target.rect.minX, width: width)
        let report = PagerTarget(
            index: geometry.nearestPageIndex(pageCount: pageCount),
            width: width,
            gestureID: gestureID
        )
        // ScrollTargetBehaviorContext is not Sendable. Only copied scalars and
        // the main-actor callback cross this boundary, after layout has finished.
        Task { @MainActor [onTarget] in
            onTarget(report)
        }
    }

    func properties(context: PropertiesContext) -> Properties {
        PagingScrollTargetBehavior().properties(context: context)
    }
}
