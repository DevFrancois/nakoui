import CoreGraphics

/// A height the bottom pane of a `SplitPane` snaps to, as a share of the
/// split's height. After SplitPaneKit's breakpoints (see `SplitPaneDrag`).
nonisolated struct SplitPaneBreakpoint: Hashable, Sendable {
    let ratio: CGFloat
    let name: String

    static let peek = SplitPaneBreakpoint(ratio: 0.25, name: "peek")
    static let half = SplitPaneBreakpoint(ratio: 0.5, name: "half")
    static let large = SplitPaneBreakpoint(ratio: 0.75, name: "large")
}
