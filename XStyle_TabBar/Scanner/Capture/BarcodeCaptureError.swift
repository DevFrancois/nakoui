/// Why the camera couldn't be set up for scanning.
nonisolated enum BarcodeCaptureError: Error {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
    /// No 1080p format reaches the scanning frame rate.
    case noFormat
}
