import UIKit

/// CAPortalLayer centers its source even when given smaller bounds. Keep that
/// projected strip across the rail, but register its long axis to the page.
struct GlassTabBarReflectionGeometry: Equatable {
    let sourceBounds: CGRect
    let portalBounds: CGRect
    let portalPosition: CGPoint
    let portalTransform: CGAffineTransform

    init?(sourceBounds: CGRect, viewportBounds: CGRect,
          sourceOrigin: CGPoint, sourceXAxis: CGPoint, sourceYAxis: CGPoint,
          axis: NSLayoutConstraint.Axis) {
        let values = [sourceBounds.minX, sourceBounds.minY, sourceBounds.width, sourceBounds.height,
                      viewportBounds.minX, viewportBounds.minY, viewportBounds.width, viewportBounds.height,
                      sourceOrigin.x, sourceOrigin.y, sourceXAxis.x, sourceXAxis.y, sourceYAxis.x, sourceYAxis.y]
        guard values.allSatisfy(\.isFinite), sourceBounds.width > 0, sourceBounds.height > 0,
              viewportBounds.width > 0, viewportBounds.height > 0 else { return nil }

        let linear = CGAffineTransform(a: sourceXAxis.x - sourceOrigin.x,
                                       b: sourceXAxis.y - sourceOrigin.y,
                                       c: sourceYAxis.x - sourceOrigin.x,
                                       d: sourceYAxis.y - sourceOrigin.y,
                                       tx: 0, ty: 0)
        let determinant = linear.a * linear.d - linear.b * linear.c
        guard determinant.isFinite, abs(determinant) > 0.000001 else { return nil }
        let halfSize = CGPoint(x: sourceBounds.width / 2, y: sourceBounds.height / 2).applying(linear)
        let convertedCenter = CGPoint(x: sourceOrigin.x + halfSize.x, y: sourceOrigin.y + halfSize.y)
        let center = axis == .vertical
            ? CGPoint(x: viewportBounds.midX, y: convertedCenter.y)
            : CGPoint(x: convertedCenter.x, y: viewportBounds.midY)

        // Clip before filtering to a narrow strip, rather than filtering a full
        // page. Inverse scaling keeps it wide enough during native deformation.
        let inverse = linear.inverted()
        let corners = [CGPoint(x: viewportBounds.minX, y: viewportBounds.minY),
                       CGPoint(x: viewportBounds.maxX, y: viewportBounds.minY),
                       CGPoint(x: viewportBounds.minX, y: viewportBounds.maxY),
                       CGPoint(x: viewportBounds.maxX, y: viewportBounds.maxY)]
        let relative = corners.map { CGPoint(x: $0.x - center.x, y: $0.y - center.y).applying(inverse) }
        var crop = sourceBounds
        if axis == .vertical {
            crop.size.width = min(sourceBounds.width, 2 * (relative.map { abs($0.x) }.max() ?? 0))
        } else {
            crop.size.height = min(sourceBounds.height, 2 * (relative.map { abs($0.y) }.max() ?? 0))
        }
        guard crop.width.isFinite, crop.height.isFinite, crop.width > 0, crop.height > 0 else { return nil }
        self.sourceBounds = sourceBounds
        portalBounds = crop
        portalPosition = center
        portalTransform = linear
    }
}
