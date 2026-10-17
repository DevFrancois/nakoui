import CoreGraphics

/// A code in upright image pixels. Unlike view points, these coordinates
/// remain valid when the camera's viewport resizes.
nonisolated struct ScanFrameGeometry: Equatable, Sendable {
    let imageQuad: Quad
    let imageSize: CGSize

    init(imageQuad: Quad, imageSize: CGSize) {
        self.imageQuad = imageQuad
        self.imageSize = imageSize
    }

    init(bufferQuad: Quad, mapper: AspectFillMapper) {
        imageQuad = bufferQuad.map { point in
            mapper.rotatesClockwise
                ? CGPoint(x: mapper.bufferSize.height - point.y, y: point.x)
                : point
        }
        imageSize = mapper.uprightSize
    }

    init(viewQuad: Quad, viewSize: CGSize, imageSize: CGSize) {
        let mapper = AspectFillMapper(bufferSize: imageSize, viewSize: viewSize, rotatesClockwise: false)
        imageQuad = viewQuad.map(mapper.bufferPoint)
        self.imageSize = imageSize
    }

    func quad(in viewSize: CGSize) -> Quad {
        let mapper = AspectFillMapper(bufferSize: imageSize, viewSize: viewSize, rotatesClockwise: false)
        return imageQuad.map(mapper.viewPoint)
    }

    /// Smooth tracking within the same image coordinate space only.
    func interpolated(to next: Self, fraction: CGFloat) -> Self {
        guard imageSize == next.imageSize else { return next }
        return Self(imageQuad: imageQuad.lerp(to: next.imageQuad, fraction), imageSize: imageSize)
    }
}
