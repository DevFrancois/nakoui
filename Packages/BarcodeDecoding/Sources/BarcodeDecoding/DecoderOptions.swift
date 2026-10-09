public struct DecoderOptions: Equatable, Sendable {
    /// Distance between neighbouring parallel scanlines, in pixels.
    public var lineSpacing: Int
    /// Pixels averaged across each scanline (along the bars) to cut sensor noise.
    public var averaging: Int
    /// Scan along image columns (bars horizontal in the image: the app's main case, since a
    /// barcode held level on the portrait screen has its bars along the landscape buffer's x).
    public var scanColumns: Bool
    /// Scan along image rows (bars vertical in the image).
    public var scanRows: Bool
    /// Also scan at ±45°.
    public var scanDiagonals: Bool
    /// Return as soon as one code reaches `minimumLines`, skipping the remaining lines.
    public var stopWhenConfirmed: Bool
    /// Lines needed before `stopWhenConfirmed` stops early.
    public var minimumLines: Int

    public init(lineSpacing: Int, averaging: Int, scanColumns: Bool, scanRows: Bool, scanDiagonals: Bool,
         stopWhenConfirmed: Bool, minimumLines: Int) {
        self.lineSpacing = lineSpacing
        self.averaging = averaging
        self.scanColumns = scanColumns
        self.scanRows = scanRows
        self.scanDiagonals = scanDiagonals
        self.stopWhenConfirmed = stopWhenConfirmed
        self.minimumLines = minimumLines
    }

    /// The app's per-frame configuration for a 1920x1080 buffer and a viewfinder-sized region.
    public static let camera = DecoderOptions(
        lineSpacing: 6, averaging: 4, scanColumns: true, scanRows: true, scanDiagonals: true,
        stopWhenConfirmed: true, minimumLines: 2
    )

    /// A dense configuration for still images, scaled to the image size.
    public static func still(width: Int, height: Int) -> DecoderOptions {
        DecoderOptions(
            lineSpacing: max(2, min(width, height) / 64), averaging: 2,
            scanColumns: true, scanRows: true, scanDiagonals: true,
            stopWhenConfirmed: false, minimumLines: 2
        )
    }
}
