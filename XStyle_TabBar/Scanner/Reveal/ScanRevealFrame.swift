import CoreGraphics

/// Every animated value of the reveal at one instant.
nonisolated struct ScanRevealFrame: Equatable, Sendable {
    /// 0 = brackets on the viewfinder, 1 = on the code.
    var bracketProgress: CGFloat = 0
    var bracketOpacity: Double = 1
    /// Whether the frozen frame covers the live camera.
    var isFrozen = false
    /// Crossfade from the sharp frozen frame to the blurred one.
    var blur: Double = 0
    /// 0 = the code patch on the code in the frame, 1 = flat at the lift target.
    var lift: CGFloat = 0
    var patchOpacity: Double = 1
    /// Seconds into the white bloom, or nil before it starts.
    var bloomTime: Double?
    var cardOpacity: Double = 1
    /// The icon's scale, or nil before it appears.
    var iconScale: CGFloat?
    var iconOpacity: Double = 1
    /// Fades the whole overlay out when the result closes.
    var overlayOpacity: Double = 1
}
