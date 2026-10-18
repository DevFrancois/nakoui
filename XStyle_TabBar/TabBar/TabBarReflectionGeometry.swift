import CoreGraphics

/// Maps window-space UI placement into the full rendered scene's point space.
/// Clipping limits sampling; it never resizes or recenters the source texture.
nonisolated struct TabBarReflectionGeometry: Equatable {
    let capsuleRect: CGRect
    let sourceSize: CGSize
    let visibleRect: CGRect

    init?(
        capsuleInWindow: CGRect,
        sourceInWindow: CGRect,
        visibleSourceInWindow: CGRect,
        reach: CGFloat = 96
    ) {
        guard Self.isValid(capsuleInWindow), Self.isValid(sourceInWindow),
              Self.isValid(visibleSourceInWindow), reach.isFinite, reach >= 0 else { return nil }

        let visible = sourceInWindow.intersection(visibleSourceInWindow)
        let samplingBounds = capsuleInWindow.insetBy(dx: -reach, dy: -reach)
        guard Self.isValid(visible), Self.isValid(samplingBounds),
              Self.isValid(samplingBounds.intersection(visible)) else { return nil }

        let capsule = capsuleInWindow.offsetBy(dx: -sourceInWindow.origin.x, dy: -sourceInWindow.origin.y)
        let clipped = visible.offsetBy(dx: -sourceInWindow.origin.x, dy: -sourceInWindow.origin.y)
        guard Self.isValid(capsule), Self.isValid(clipped) else { return nil }

        capsuleRect = capsule
        sourceSize = sourceInWindow.size
        visibleRect = clipped
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite &&
            rect.origin.x.isFinite && rect.origin.y.isFinite &&
            rect.size.width.isFinite && rect.size.height.isFinite &&
            rect.size.width > 0 && rect.size.height > 0 &&
            rect.maxX.isFinite && rect.maxY.isFinite
    }
}
