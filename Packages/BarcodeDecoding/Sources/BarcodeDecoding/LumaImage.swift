/// A read-only 8-bit luma image, laid out like plane 0 of a 420f CVPixelBuffer:
/// row-major, `bytesPerRow >= width`, row 0 at the top.
public struct LumaImage {
    public let pixels: UnsafePointer<UInt8>
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    public init(pixels: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }
}
