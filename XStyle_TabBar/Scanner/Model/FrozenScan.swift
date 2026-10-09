import CoreGraphics

/// The frame a code was found in, prepared for the reveal animation. The
/// images are immutable, so it's safe to hand across actors.
nonisolated struct FrozenScan: @unchecked Sendable {
    /// The whole frame, upright, at buffer resolution. Drawn aspect-filled it
    /// lines up with the live preview.
    let sharp: CGImage
    /// The same frame, downscaled, blurred and frosted.
    let blurred: CGImage
    /// The code cut out and flattened at its lifted size, with `patchPadding`
    /// points of transparent border so warped edges stay smooth.
    let patch: CGImage
    let patchPadding: CGFloat
    /// The code in this frame, in full-screen view points.
    let quad: Quad
    /// Where the code goes from here.
    let layout: RevealLayout
}
