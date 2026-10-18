import CoreGraphics

nonisolated extension CGRect {
    /// Non-null and finite, with a positive width and height.
    var hasFiniteArea: Bool {
        !isNull && !isInfinite && origin.x.isFinite && origin.y.isFinite &&
            size.width.isFinite && size.height.isFinite &&
            size.width > 0 && size.height > 0 &&
            maxX.isFinite && maxY.isFinite
    }
}
