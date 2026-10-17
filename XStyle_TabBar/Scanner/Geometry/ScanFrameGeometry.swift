import CoreGraphics

/// A code in upright image pixels. Unlike view points, these coordinates
/// remain valid when the camera's viewport resizes.
nonisolated struct ScanFrameGeometry: Equatable, Sendable {
    let imageQuad: Quad
    let imageSize: CGSize
    let sourceRotation: CameraImageRotation
    let sourceSize: CGSize
    private let imageOffset: CGPoint

    init(imageQuad: Quad, imageSize: CGSize) {
        self.imageQuad = imageQuad
        self.imageSize = imageSize
        sourceRotation = .unrotated
        sourceSize = imageSize
        imageOffset = .zero
    }

    private init(imageQuad: Quad, imageSize: CGSize, sourceRotation: CameraImageRotation, sourceSize: CGSize, imageOffset: CGPoint) {
        self.imageQuad = imageQuad
        self.imageSize = imageSize
        self.sourceRotation = sourceRotation
        self.sourceSize = sourceSize
        self.imageOffset = imageOffset
    }

    init(bufferQuad: Quad, mapper: AspectFillMapper, renderedImageBounds: CGRect? = nil) {
        let bounds = renderedImageBounds ?? CGRect(origin: .zero, size: mapper.uprightSize)
        let offset = CGPoint(x: -bounds.minX, y: bounds.maxY - mapper.uprightSize.height)
        imageQuad = bufferQuad.map {
            let point = $0.applying(mapper.rotation.imageTransform(for: mapper.bufferSize))
            return CGPoint(x: point.x + offset.x, y: point.y + offset.y)
        }
        imageSize = bounds.size
        sourceRotation = mapper.rotation
        sourceSize = mapper.bufferSize
        imageOffset = offset
    }

    init(viewQuad: Quad, viewSize: CGSize, imageSize: CGSize) {
        let mapper = AspectFillMapper(bufferSize: imageSize, viewSize: viewSize, rotation: .unrotated)
        imageQuad = viewQuad.map(mapper.bufferPoint)
        self.imageSize = imageSize
        sourceRotation = .unrotated
        sourceSize = imageSize
        imageOffset = .zero
    }

    func quad(in viewSize: CGSize) -> Quad {
        let mapper = AspectFillMapper(bufferSize: imageSize, viewSize: viewSize, rotation: .unrotated)
        return imageQuad.map(mapper.viewPoint)
    }

    /// A preview can rotate between tracking frames. Reproject the retained raw
    /// pixel coordinates immediately instead of interpolating across orientations.
    func reoriented(to rotation: CameraImageRotation) -> Self {
        guard rotation != sourceRotation else { return self }
        let inverse = sourceRotation.imageTransform(for: sourceSize).inverted()
        let rawQuad = imageQuad.map { CGPoint(x: $0.x - imageOffset.x, y: $0.y - imageOffset.y).applying(inverse) }
        return Self(bufferQuad: rawQuad, mapper: AspectFillMapper(
            bufferSize: sourceSize, viewSize: imageSize, rotation: rotation
        ))
    }

    /// Smooth tracking within the same image coordinate space only.
    func interpolated(to next: Self, fraction: CGFloat) -> Self {
        guard imageSize == next.imageSize, sourceRotation == next.sourceRotation,
              sourceSize == next.sourceSize, imageOffset == next.imageOffset else { return next }
        return Self(imageQuad: imageQuad.lerp(to: next.imageQuad, fraction), imageSize: imageSize,
                    sourceRotation: sourceRotation, sourceSize: sourceSize, imageOffset: imageOffset)
    }
}
