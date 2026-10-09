/// A point in continuous image coordinates: pixel `i` covers `[i, i + 1)`, so the centre of
/// pixel (3, 5) is (3.5, 5.5). Divide by the image width/height for capture-device points.
public struct BarcodePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
