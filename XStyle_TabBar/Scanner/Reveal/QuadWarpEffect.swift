import SwiftUI

/// Warps a view in perspective so its bounds, less `padding`, land on `quad`,
/// given in the view's own coordinates. A quad that isn't convex and upright
/// would fling the view past the horizon, so it gets the quad's bounding box
/// instead. (`visualEffect`'s `transformEffect` would drop the perspective
/// terms, so this is a geometry effect.)
nonisolated struct QuadWarpEffect: GeometryEffect {
    var quad: Quad
    var padding: CGFloat = 0

    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let source = CGRect(origin: .zero, size: size).insetBy(dx: padding, dy: padding)
        let target = quad.isConvexAndUpright ? quad : Quad(quad.boundingBox)
        return Homography.rect(source, to: target)?.projectionTransform ?? ProjectionTransform()
    }
}
