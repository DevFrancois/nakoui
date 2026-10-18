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
        reach: CGFloat = TabBarReflectionSettings.Parameter.samplingDistance.range.upperBound
    ) {
        guard capsuleInWindow.hasFiniteArea, sourceInWindow.hasFiniteArea,
              visibleSourceInWindow.hasFiniteArea, reach.isFinite, reach >= 0 else { return nil }

        let visible = sourceInWindow.intersection(visibleSourceInWindow)
        let samplingBounds = capsuleInWindow.insetBy(dx: -reach, dy: -reach)
        guard visible.hasFiniteArea, samplingBounds.hasFiniteArea,
              samplingBounds.intersection(visible).hasFiniteArea else { return nil }

        let capsule = capsuleInWindow.offsetBy(dx: -sourceInWindow.origin.x, dy: -sourceInWindow.origin.y)
        let clipped = visible.offsetBy(dx: -sourceInWindow.origin.x, dy: -sourceInWindow.origin.y)
        guard capsule.hasFiniteArea, clipped.hasFiniteArea else { return nil }

        capsuleRect = capsule
        sourceSize = sourceInWindow.size
        visibleRect = clipped
    }
}
