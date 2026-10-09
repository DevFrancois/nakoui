import SwiftUI

/// The dimmed area around the viewfinder: the whole frame with the window cut
/// out. Fill it with the even-odd rule.
nonisolated struct ViewfinderCutout: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(
            in: ScannerMetrics.viewfinderRect(in: rect),
            cornerSize: CGSize(width: ScannerMetrics.viewfinderCornerRadius, height: ScannerMetrics.viewfinderCornerRadius)
        )
        return path
    }
}
