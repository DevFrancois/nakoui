/// Where the camera stands.
enum ScannerState {
    /// Not running: the tab hasn't been shown yet, or was left.
    case idle
    case scanning
    /// Camera access was refused or restricted.
    case denied
    /// There's no camera, or it couldn't start.
    case unavailable
}
