import CoreGraphics

/// Shared sizes for the scanner. Nonisolated because the capture code reads
/// the viewfinder geometry too.
nonisolated enum ScannerMetrics {
    /// Share of the camera pane's width the viewfinder spans...
    static let viewfinderWidthFraction = 0.82
    static let viewfinderMaxWidth = 360.0
    /// ...and the most of its height, so the viewfinder shrinks as the result
    /// pane grows, live while it's dragged.
    static let viewfinderMaxHeightFraction = 0.4
    /// Width over height: wide, like the product barcodes it frames.
    static let viewfinderAspectRatio = 1.6
    /// The viewfinder's center, as a share of the camera pane's height: the
    /// middle, as the pane sits below the status bar with its controls over
    /// its foot.
    static let viewfinderCenterFraction = 0.5
    static let viewfinderCornerRadius = 24.0
    /// A bracket's straight part, beyond its rounded corner.
    static let bracketLength = 30.0
    static let bracketLineWidth = 5.0
    /// How far brackets sit outside the code they hug.
    static let bracketOutset = 6.0
    /// Keeps white brackets visible on white labels.
    static let bracketShadowOpacity = 0.35
    static let scrimOpacity = 0.45

    /// Wide windows at least this wide put the result pane beside the camera.
    static let sideBySideMinimumWidth = 600.0
    /// The result pane's share of the width side by side.
    static let sideBySideResultFraction = 0.38

    /// Whether a scanner of `size` puts its panes side by side, such as the
    /// Duo unfolded or a phone in landscape.
    static func usesSideBySide(in size: CGSize) -> Bool {
        size.width > size.height && size.width >= sideBySideMinimumWidth
    }

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
    /// How long the viewfinder must stay put before the camera focuses and
    /// meters on it, in seconds, so a moving sheet doesn't re-meter every frame.
    static let meteringSettleDelay = 0.1

    // Flicker detection (see `FlickerDetector`).
    /// Pulses per second of the lights to look for: lamps on 50 Hz mains.
    /// Exposures of whole pulses show them without bands.
    static let flickerRate = 100
    /// Many such lamps light the two halves of each mains cycle unevenly,
    /// a faint flicker at half the rate that one-pulse exposures leave.
    static let unevenFlickerRate = 50
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
    /// The same for uneven pulses, which are much fainter: about 0.3%, still
    /// visible as a slow shimmer.
    static let unevenFlickerMinimumChange: Float = 0.003
    /// How many times more out-of-phase frames must differ than in-phase ones.
    static let flickerChangeRatio: Float = 3
    /// Flicker is seen once this many of the latest votes say so.
    static let flickerVoteWindow = 12
    static let flickerVotesNeeded = 8
    /// Under flickering light the meter's ISO steps are ignored when smaller
    /// than this, in EV, so the image doesn't shimmer as they jitter.
    static let flickerMeteringDeadband = 0.15

    /// The viewfinder's frame in the camera pane's `bounds`. The brackets, the
    /// camera's scan region and the reveal all come from here, so they match
    /// at every pane size.
    static func viewfinderRect(in bounds: CGRect) -> CGRect {
        // A share of the pane's height, and never past its edges around the
        // optical center.
        let edgeLimit = 2 * min(viewfinderCenterFraction, 1 - viewfinderCenterFraction)
        let availableHeight = bounds.height * min(viewfinderMaxHeightFraction, edgeLimit)
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
