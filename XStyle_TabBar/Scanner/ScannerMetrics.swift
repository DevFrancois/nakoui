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
    /// Height of the controls under the viewfinder: the zoom buttons' capsule
    /// and the flashlight button.
    static let cameraControlSize = 46.0
    /// The zoom buttons' inset inside their capsule.
    static let zoomButtonInset = 4.0

    // Flicker detection (see `FlickerDetector`).
    /// Pulses per second of the lights to look for: lamps on 50 Hz mains.
    /// Exposures of whole pulses show them without bands.
    static let flickerRate = 100
    /// The luma plane is sampled every this many rows and columns.
    static let flickerRowStep = 4
    static let flickerColumnStep = 16
    /// Frames are compared with earlier ones up to this many seconds old.
    static let flickerHistoryDuration = 0.3
    /// How close, as a share of a pulse, a time gap must come to a whole
    /// number of pulses to count as in phase, or to half a pulse off to
    /// count as out of phase.
    static let flickerInPhaseTolerance = 0.1
    static let flickerOutOfPhaseTolerance = 0.3
    /// The least mean change in log brightness between out-of-phase frames
    /// that counts as flicker: about 2%.
    static let flickerMinimumChange: Float = 0.02
    /// How many times more out-of-phase frames must differ than in-phase ones.
    static let flickerChangeRatio: Float = 3
    /// Flicker is seen once this many of the latest votes say so.
    static let flickerVoteWindow = 12
    static let flickerVotesNeeded = 8

    /// The viewfinder's frame in a full-screen `bounds`. The on-screen frame
    /// and the camera's scan region both come from here, so they match.
    static func viewfinderRect(in bounds: CGRect) -> CGRect {
        // Keep both edges in a short window while retaining the same preferred
        // width and optical center when there is enough room.
        let availableHeight = bounds.height * 2 * min(viewfinderCenterFraction, 1 - viewfinderCenterFraction)
        let width = max(0, min(bounds.width * viewfinderWidthFraction, viewfinderMaxWidth, availableHeight * viewfinderAspectRatio))
        let height = width / viewfinderAspectRatio
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.minY + bounds.height * viewfinderCenterFraction - height / 2,
            width: width,
            height: height
        )
    }
}
