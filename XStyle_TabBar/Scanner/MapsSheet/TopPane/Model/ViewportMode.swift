//
//  ViewportMode.swift
//  MapsIOS26BottomSheet
//

/// How the top pane makes way for the rising sheet. A debug setting, to compare them.
nonisolated enum ViewportMode: String, CaseIterable, Sendable {
    /// The pane shrinks above the sheet down to medium, then recedes as the sheet covers it.
    case resizing
    /// The pane keeps its frame and size, and the sheet slides over it.
    case fixed
    /// The pane keeps its frame and the sheet slides over it, while it scales down a little as the sheet opens and
    /// more as it reaches full; see `PaneTuning.recedingScale`.
    case receding
}
