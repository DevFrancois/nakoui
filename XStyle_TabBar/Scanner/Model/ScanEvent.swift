import CoreGraphics

/// What the frame analyzer reports to the scanner.
nonisolated enum ScanEvent: Sendable {
    /// A new code was confirmed. The analyzer then tracks it.
    case detected(ScanDetection)
    /// The tracked code moved in its source image.
    case tracked(ScanFrameGeometry)
}
