import CoreGraphics

/// A confirmed code in a live frame, placed on screen.
nonisolated struct ScanDetection: Sendable {
    let code: ScannedCode
    /// The code with its quiet zones and digits, in reading orientation, in
    /// full-screen view points.
    let quad: Quad
}
