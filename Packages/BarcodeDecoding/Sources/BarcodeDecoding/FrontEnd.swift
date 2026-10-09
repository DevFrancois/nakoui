/// How a profile is turned into edges.
enum FrontEnd {
    /// `EdgeDetector`, with its slope floor in profile units per sample.
    case inflections(minSlope: Int)
    /// `ThresholdEdgeDetector`, with the profile units per grey level.
    case threshold(scale: Int)
}
