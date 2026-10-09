import SwiftUI

/// The viewfinder's corner brackets, drawn exactly as the reveal draws them
/// at the start of their flight, so the hand-off is seamless.
nonisolated struct ViewfinderBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        QuadBrackets(quad: Quad(ScannerMetrics.viewfinderRect(in: rect))).path(in: rect)
    }
}
