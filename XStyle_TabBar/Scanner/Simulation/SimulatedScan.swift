import SwiftUI

/// A pretend scan of the placeholder backdrop's barcode label, so the reveal
/// can play in the Simulator and in previews, where there's no camera.
struct SimulatedScan {
    let screenSize: CGSize
    let displayScale: CGFloat

    /// The label in the backdrop, in full-screen points, kept inside its
    /// rounded corners.
    var codeQuad: Quad {
        ScannerBackdropPlaceholder.labelQuad(in: CGRect(origin: .zero, size: screenSize))
            .expanded(leading: -3, trailing: -3, top: -3, bottom: -3)
    }

    /// The backdrop rendered as if the camera had frozen on it.
    func frozenScan() async -> FrozenScan? {
        let renderer = ImageRenderer(content: ScannerBackdropPlaceholder()
            .frame(width: screenSize.width, height: screenSize.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = displayScale
        guard let image = renderer.cgImage else { return nil }
        let scale = displayScale
        return await FrozenScanRenderer.render(
            image, codeQuad: codeQuad.map { CGPoint(x: $0.x * scale, y: $0.y * scale) },
            viewQuad: codeQuad, viewSize: screenSize, displayScale: displayScale
        )
    }

    /// A reveal of `code` that froze right on time, for pinning any moment.
    func reveal(of code: ScannedCode) async -> ScanReveal {
        let viewfinder = Quad(ScannerMetrics.viewfinderRect(in: CGRect(origin: .zero, size: screenSize)))
        let start = Date.now
        var reveal = ScanReveal(code: code, viewfinder: viewfinder, liveQuad: codeQuad, startDate: start)
        if let frozen = await frozenScan() {
            reveal.freeze(frozen, at: start.addingTimeInterval(ScanRevealTimeline.freeze))
        }
        return reveal
    }
}
