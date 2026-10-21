/// How a found code is shown in the camera. A debug setting, to compare them.
nonisolated enum ScanRevealStyle: String, CaseIterable, Sendable {
    /// The camera stays live: the brackets close on the code and follow it,
    /// then let go after `ScanRevealTimeline.liveHold`.
    case liveBrackets
    /// Code Scanner's reveal: the frame freezes, the code lifts off it and
    /// blooms into a card with the product icon.
    case fullReveal
}
