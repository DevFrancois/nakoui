/// A half-open pixel rectangle of the image to scan: `minX..<maxX`, `minY..<maxY`.
/// The decoder may read a little outside it (to check quiet zones) but stays inside the image.
/// A code whose centre lies outside the region is not reported.
public struct ScanRegion: Equatable, Sendable {
    public var minX: Int
    public var minY: Int
    public var maxX: Int
    public var maxY: Int

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Int { maxX - minX }
    public var height: Int { maxY - minY }
}
