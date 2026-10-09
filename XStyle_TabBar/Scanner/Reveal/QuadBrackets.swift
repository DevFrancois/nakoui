import SwiftUI

/// Four rounded corner brackets that follow any convex quad, so they can fly
/// from the viewfinder onto a code seen in perspective. Drawn in the
/// coordinates the quad was computed in.
nonisolated struct QuadBrackets: Shape {
    var quad: Quad
    /// Each arm's length from the corner, capped to a share of its edge.
    var armLength: CGFloat = ScannerMetrics.viewfinderCornerRadius + ScannerMetrics.bracketLength
    var cornerRadius: CGFloat = ScannerMetrics.viewfinderCornerRadius

    func path(in rect: CGRect) -> Path {
        let corners = quad.corners
        var path = Path()
        for i in 0..<4 {
            let corner = corners[i], previous = corners[(i + 3) % 4], next = corners[(i + 1) % 4]
            let previousLength = corner.distance(to: previous), nextLength = corner.distance(to: next)
            guard previousLength > 1, nextLength > 1 else { continue }
            let arm = min(armLength, previousLength * 0.3, nextLength * 0.3)
            let radius = min(cornerRadius, arm * 0.6)
            let start = corner.lerp(to: previous, arm / previousLength)
            let end = corner.lerp(to: next, arm / nextLength)
            path.move(to: start)
            path.addArc(tangent1End: corner, tangent2End: end, radius: radius)
            path.addLine(to: end)
        }
        return path
    }
}
