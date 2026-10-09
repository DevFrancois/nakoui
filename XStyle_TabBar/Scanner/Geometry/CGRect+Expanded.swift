import CoreGraphics

nonisolated extension CGRect {
    /// Grown around its centre to at least `size`, then kept inside the unit
    /// square. For capture-device rects of interest, which have minimum sizes.
    func expanded(toAtLeast size: CGSize) -> CGRect {
        let width = Swift.min(Swift.max(self.width, size.width), 1)
        let height = Swift.min(Swift.max(self.height, size.height), 1)
        return CGRect(
            x: Swift.min(Swift.max(midX - width / 2, 0), 1 - width),
            y: Swift.min(Swift.max(midY - height / 2, 0), 1 - height),
            width: width,
            height: height
        )
    }
}
