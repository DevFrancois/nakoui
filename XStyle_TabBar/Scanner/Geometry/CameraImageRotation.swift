import CoreGraphics

/// The preview coordinator's clockwise rotation, applied to raw sensor pixels.
/// It is independent of the window's aspect ratio and the device idiom.
nonisolated struct CameraImageRotation: Equatable, Sendable {
    let degrees: CGFloat

    static let unrotated = Self(degrees: 0)
    /// The synthetic camera produces a landscape buffer from a portrait fixture.
    static let simulated = Self(degrees: 90)

    init(degrees: CGFloat) {
        precondition(degrees.isFinite)
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        self.degrees = remainder < 0 ? remainder + 360 : remainder
    }

    /// Raw pixels and image pixels both have their origin at the top leading corner.
    func imageTransform(for bufferSize: CGSize) -> CGAffineTransform {
        normalizedTransform(for: bufferSize, clockwise: true)
    }

    /// Core Image's origin is at the bottom left, so the rotation sign reverses.
    func coreImageTransform(for bufferSize: CGSize) -> CGAffineTransform {
        normalizedTransform(for: bufferSize, clockwise: false)
    }

    func imageSize(for bufferSize: CGSize) -> CGSize {
        CGRect(origin: .zero, size: bufferSize).applying(imageTransform(for: bufferSize)).size
    }

    private func normalizedTransform(for size: CGSize, clockwise: Bool) -> CGAffineTransform {
        let radians = degrees * .pi / 180 * (clockwise ? 1 : -1)
        // Exact quarter turns must not acquire a fractional pixel border when
        // Core Image rounds its output extent to integral pixel dimensions.
        let cosine = snapped(cos(radians))
        let sine = snapped(sin(radians))
        let rotation = CGAffineTransform(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
        let bounds = CGRect(origin: .zero, size: size).applying(rotation)
        return rotation.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }

    private func snapped(_ value: CGFloat) -> CGFloat {
        abs(value) < 1e-12 ? 0 : value
    }
}
