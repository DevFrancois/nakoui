import CoreGraphics

/// Shared sizes for the scanner. Nonisolated because the capture code reads
/// the viewfinder geometry too.
nonisolated enum ScannerMetrics {
    /// Share of the screen width the viewfinder spans.
    static let viewfinderWidthFraction = 0.82
    static let viewfinderMaxWidth = 360.0
    /// Width over height: wide, like the product barcodes it frames.
    static let viewfinderAspectRatio = 1.6
    /// The viewfinder's center, as a share of the screen height. A little
    /// above the middle, clear of the tab bar.
    static let viewfinderCenterFraction = 0.45
    static let viewfinderCornerRadius = 24.0
    /// A bracket's straight part, beyond its rounded corner.
    static let bracketLength = 30.0
    static let bracketLineWidth = 5.0
    /// How far brackets sit outside the code they hug.
    static let bracketOutset = 6.0
    /// Keeps white brackets visible on white labels.
    static let bracketShadowOpacity = 0.35
    static let scrimOpacity = 0.45
    static let hintSpacing = 24.0

    /// The camera also scans this far around the viewfinder, as a share of
    /// its width, so a code at its edge still has its quiet zones.
    static let scanMarginFraction = 0.15
    /// Room around the bars for the quiet zones and printed digits, in
    /// modules: what the brackets hug and the reveal lifts.
    static let outlineSideModules = 8.0
    static let outlineTopModules = 3.0
    static let outlineBottomModules = 11.0

    /// The narrowest product barcode to keep sharp, in millimeters: an EAN-13
    /// or UPC-A printed at its smallest allowed size, 80%.
    static let minimumCodeWidth = 30.0
    /// Share of the viewfinder that code should span when held at the
    /// camera's closest focus distance.
    static let minimumCodeViewfinderFill = 0.6
    /// Auto zoom never goes past this, so aiming stays easy.
    static let maximumAutoZoom = 3.0
    /// The user can pinch to here: further in, the camera only enlarges blur.
    static let maximumZoom = 5.0
    /// How fast the zoom buttons ease the zoom, in doublings per second.
    static let zoomRampRate: Float = 4

    /// The viewfinder's frame in a full-screen `bounds`. The on-screen frame
    /// and the camera's scan region both come from here, so they match.
    static func viewfinderRect(in bounds: CGRect) -> CGRect {
        let width = min(bounds.width * viewfinderWidthFraction, viewfinderMaxWidth)
        let height = width / viewfinderAspectRatio
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.minY + bounds.height * viewfinderCenterFraction - height / 2,
            width: width,
            height: height
        )
    }
}
