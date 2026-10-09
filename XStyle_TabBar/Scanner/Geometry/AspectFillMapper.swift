import CoreGraphics

/// Maps between camera buffer pixels and the points of a full-screen view
/// showing the buffer turned upright and aspect-filled: the geometry of
/// `AVCaptureVideoPreviewLayer` with `.resizeAspectFill` and a 90° connection,
/// and of the frozen frame drawn with `.scaledToFill()`.
///
/// Buffer pixels use continuous coordinates: pixel (i, j) spans
/// [i, i + 1) × [j, j + 1).
nonisolated struct AspectFillMapper: Equatable, Sendable {
    /// The buffer as delivered, e.g. 1920 x 1080 for a landscape sensor.
    var bufferSize: CGSize
    /// The view, in points.
    var viewSize: CGSize
    /// True when the buffer is turned 90° clockwise to stand upright: the back
    /// camera on a portrait iPhone with an unrotated data connection.
    var rotatesClockwise: Bool

    /// The buffer's size once upright.
    var uprightSize: CGSize {
        rotatesClockwise ? CGSize(width: bufferSize.height, height: bufferSize.width) : bufferSize
    }

    /// View points per upright pixel: the larger ratio, so the image covers the view.
    var scale: CGFloat {
        let upright = uprightSize
        guard upright.width > 0, upright.height > 0 else { return 1 }
        return max(viewSize.width / upright.width, viewSize.height / upright.height)
    }

    /// Where the upright image's origin lands. The cropped axis is negative.
    var offset: CGPoint {
        let upright = uprightSize
        return CGPoint(x: (viewSize.width - upright.width * scale) / 2, y: (viewSize.height - upright.height * scale) / 2)
    }

    func viewPoint(fromBuffer p: CGPoint) -> CGPoint {
        let upright = rotatesClockwise ? CGPoint(x: bufferSize.height - p.y, y: p.x) : p
        return CGPoint(x: upright.x * scale + offset.x, y: upright.y * scale + offset.y)
    }

    func bufferPoint(fromView v: CGPoint) -> CGPoint {
        let upright = CGPoint(x: (v.x - offset.x) / scale, y: (v.y - offset.y) / scale)
        return rotatesClockwise ? CGPoint(x: upright.y, y: bufferSize.height - upright.x) : upright
    }

    /// The buffer-pixel bounding box of a view rect.
    func bufferRect(fromView rect: CGRect) -> CGRect {
        let a = bufferPoint(fromView: CGPoint(x: rect.minX, y: rect.minY))
        let b = bufferPoint(fromView: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
