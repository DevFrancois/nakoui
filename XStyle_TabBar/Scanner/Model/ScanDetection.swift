import CoreGraphics

/// A confirmed code in a live frame, independent of the viewport size.
nonisolated struct ScanDetection: Sendable {
    let code: ScannedCode
    /// The code with its quiet zones and digits, in reading orientation.
    let geometry: ScanFrameGeometry
}
